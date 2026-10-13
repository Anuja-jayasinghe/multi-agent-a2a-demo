import asyncio
import os

from google.adk.runners import Runner
from google.genai import types

from a2a.helpers import get_message_text, new_task_from_user_message, new_text_part
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater

from agent import AgentResponse
from tickets import mark_fulfilled

_INCIDENT_KEYWORDS = ('incident', 'outage', 'cannot reach', "can't reach", 'down')

# Deterministic, executor-orchestrated progress narration for the incident
# flow — the *diagnosis* itself always comes from a real LLM call; these are
# just the "still working..." steps a real long-running investigation
# would report, staged so cancelTask has real windows to interrupt.
_INVESTIGATION_STEPS = (
    'Checking network logs...',
    'Correlating with recent infrastructure changes...',
)
_STEP_DELAY_SECONDS = 2

# Same idea for a hardware ticket that was actually just created (see
# _resolve_from_response) -- the ticket itself is real and immediate, but
# real fulfillment (manager approval, ordering, prep) takes real time.
# Read once at process start -- see orchestrator/README.md for why an env
# override only affects agent processes started after it's set.
_PROVISIONING_STEPS = (
    'Routing to manager for approval...',
    'Approved — ordering hardware...',
    'Preparing for pickup...',
)
_PROVISIONING_STEP_DELAY_SECONDS = int(
    os.environ.get('HARDWARE_PROVISIONING_STEP_DELAY_SECONDS', '200')
)

# task_id -> asyncio.Event, set by cancel() to interrupt a pending
# incident investigation or hardware-provisioning flow's staged delays.
# In-memory only. Registered once per task in execute() so it covers
# whichever flow actually runs.
_cancel_signals: dict[str, asyncio.Event] = {}


class DigiOpsAgentExecutor(AgentExecutor):
    """DigiOps Agent (IT Helpdesk) — Google ADK + real Anthropic backing."""

    def __init__(self, runner: Runner) -> None:
        self._runner = runner

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        query = get_message_text(context.message) or ''
        is_incident = any(k in query.lower() for k in _INCIDENT_KEYWORDS)

        user_id, session_id = await self._ensure_session(context)
        task = context.current_task
        if task is None:
            task = new_task_from_user_message(context.message)
            await event_queue.enqueue_event(task)
        updater = TaskUpdater(
            event_queue=event_queue, task_id=task.id, context_id=task.context_id
        )
        await updater.submit()

        # Registered once per task here rather than per-flow: create_ticket
        # is available to the LLM in both the plain and incident-diagnosis
        # flows below, so either one can end up needing a cancellable
        # provisioning wait via _resolve_from_response.
        cancel_signal = asyncio.Event()
        _cancel_signals[task.id] = cancel_signal
        try:
            if is_incident:
                await self._run_incident_flow(
                    query, user_id, session_id, updater, cancel_signal
                )
            else:
                await self._run_llm_flow(
                    query, user_id, session_id, updater, cancel_signal
                )
        finally:
            _cancel_signals.pop(task.id, None)

    async def _ensure_session(self, context: RequestContext) -> tuple[str, str]:
        user_id = 'a2a_user'
        session_id = context.message.context_id or context.context_id
        session = await self._runner.session_service.get_session(
            app_name=self._runner.app_name, user_id=user_id, session_id=session_id
        )
        if session is None:
            await self._runner.session_service.create_session(
                app_name=self._runner.app_name, user_id=user_id, session_id=session_id
            )
        return user_id, session_id

    async def _call_llm(
        self, query: str, user_id: str, session_id: str
    ) -> tuple[AgentResponse | None, dict | None]:
        """Runs the real ADK Runner and parses its structured response.
        Returns (None, None) if the model produced no final response or the
        response didn't parse as the expected schema.

        The second element is create_ticket's own real return value (ticket
        id, item, status, over_catalog, severity) iff it was actually
        called during *this* run — detected from this call's own event
        stream (Event.get_function_responses()), not from any shared
        state, so it can't be confused with a different concurrent
        request's ticket."""
        content = types.Content(role='user', parts=[types.Part.from_text(text=query)])
        final_text = None
        ticket_info: dict | None = None
        async for event in self._runner.run_async(
            user_id=user_id, session_id=session_id, new_message=content
        ):
            for func_response in event.get_function_responses():
                if func_response.name == 'create_ticket':
                    ticket_info = func_response.response
            if event.is_final_response() and event.content and event.content.parts:
                final_text = event.content.parts[0].text

        if final_text is None:
            return None, ticket_info
        try:
            return AgentResponse.model_validate_json(final_text.strip()), ticket_info
        except ValueError:
            return None, ticket_info

    async def _run_llm_flow(
        self,
        query: str,
        user_id: str,
        session_id: str,
        updater: TaskUpdater,
        cancel_signal: asyncio.Event,
    ) -> None:
        """FAQ Q&A and hardware-ticket handling — both go through the same
        real LLM tool-calling path, so there's no separate code branch for
        the two: the model decides whether to call create_ticket/get_ticket
        or just answer directly."""
        await updater.start_work()
        response, ticket_info = await self._call_llm(query, user_id, session_id)
        await self._resolve_from_response(updater, response, ticket_info, cancel_signal)

    async def _run_incident_flow(
        self,
        query: str,
        user_id: str,
        session_id: str,
        updater: TaskUpdater,
        cancel_signal: asyncio.Event,
    ) -> None:
        """Staged progress narration (deterministic, executor-controlled) is
        purely how a real long-running investigation reports being alive —
        the actual diagnosis at the end always comes from a real LLM call.
        cancelTask can interrupt at any staged step."""
        for step in _INVESTIGATION_STEPS:
            await updater.start_work(
                message=updater.new_agent_message(parts=[new_text_part(step)])
            )
            try:
                await asyncio.wait_for(
                    cancel_signal.wait(), timeout=_STEP_DELAY_SECONDS
                )
                return  # cancel() already handled the task-state transition
            except asyncio.TimeoutError:
                pass

        diagnosis_prompt = (
            f'Investigate this reported incident and give a diagnosis '
            f'and next step: {query}'
        )
        response, ticket_info = await self._call_llm(
            diagnosis_prompt, user_id, session_id
        )
        await self._resolve_from_response(updater, response, ticket_info, cancel_signal)

    async def _resolve_from_response(
        self,
        updater: TaskUpdater,
        response: AgentResponse | None,
        ticket_info: dict | None,
        cancel_signal: asyncio.Event,
    ) -> None:
        if response is None:
            await updater.failed(
                message=updater.new_agent_message(
                    parts=[new_text_part('No usable response produced.')]
                )
            )
            return

        reply = updater.new_agent_message(parts=[new_text_part(response.message)])
        if response.status == 'completed' and ticket_info is not None:
            # A real ticket now exists (created above, for real, immediately
            # — that part isn't staged). Only an over-catalog request needs
            # real staged manager approval; a standard-catalog item (laptop,
            # monitor, docking station, headset) fulfills fast, as a real
            # request genuinely would.
            if ticket_info.get('over_catalog'):
                await self._run_provisioning_flow(
                    updater, ticket_info['ticket_id'], response.message, reply, cancel_signal
                )
            else:
                mark_fulfilled(ticket_info['ticket_id'])
                await updater.add_artifact(parts=[new_text_part(response.message)])
                await updater.complete(message=reply)
        elif response.status == 'completed':
            await updater.add_artifact(parts=[new_text_part(response.message)])
            await updater.complete(message=reply)
        elif response.status == 'input-required':
            await updater.requires_input(message=reply)
        else:
            await updater.failed(message=reply)

    async def _run_provisioning_flow(
        self,
        updater: TaskUpdater,
        ticket_id: str,
        message_text: str,
        reply,
        cancel_signal: asyncio.Event,
    ) -> None:
        """Staged, cancellable narration of real-world hardware fulfillment
        after a real over-catalog ticket was just created. Same shape as
        _run_incident_flow: deterministic progress steps, real work (the
        ticket) already done, cancelTask can interrupt at any step."""
        for step in _PROVISIONING_STEPS:
            await updater.start_work(
                message=updater.new_agent_message(parts=[new_text_part(step)])
            )
            try:
                await asyncio.wait_for(
                    cancel_signal.wait(), timeout=_PROVISIONING_STEP_DELAY_SECONDS
                )
                return  # cancel() already handled the task-state transition
            except asyncio.TimeoutError:
                pass

        mark_fulfilled(ticket_id)
        await updater.add_artifact(parts=[new_text_part(message_text)])
        await updater.complete(message=reply)

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        task = context.current_task
        if task is None:
            return
        signal = _cancel_signals.get(task.id)
        updater = TaskUpdater(
            event_queue=event_queue, task_id=task.id, context_id=task.context_id
        )
        await updater.cancel()
        if signal is not None:
            signal.set()
