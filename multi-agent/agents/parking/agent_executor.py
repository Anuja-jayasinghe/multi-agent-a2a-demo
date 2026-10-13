import asyncio
import re

from google.adk.runners import Runner
from google.genai import types

from a2a.helpers import (
    get_message_text,
    new_task_from_user_message,
    new_text_message,
    new_text_part,
)
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater

from agent import AgentResponse
from data import create_reservation, find_mentioned_spot, is_free, resolve_date

# Word-boundary match on the imperative verb only -- a plain substring check
# on "reserve"/"book" also matches "reserved"/"booked" in a purely
# informational question like "who reserved spot B01?" or "is B01 booked?",
# incorrectly routing it into the task-creating reservation flow instead of
# the plain-message availability flow.
_RESERVE_PATTERN = re.compile(r'\b(reserve|book)\b', re.IGNORECASE)

# How long a reservation stays cancelable before it resolves — long enough
# for a real cancelTask call to land inside the window, short enough not to
# make manual testing annoying.
_CHECK_DELAY_SECONDS = 4

# task_id -> asyncio.Event, set by cancel() to interrupt a pending
# reservation's artificial delay. In-memory only, matches InMemoryTaskStore.
_cancel_signals: dict[str, asyncio.Event] = {}


class ParkingAgentExecutor(AgentExecutor):
    """Parking Manager Agent — real Anthropic-backed language understanding,
    deterministic reservation lifecycle (unchanged from before)."""

    def __init__(self, runner: Runner) -> None:
        self._runner = runner

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        query = get_message_text(context.message) or ''
        wants_reservation = _RESERVE_PATTERN.search(query) is not None
        user_id, session_id = await self._ensure_session(context)

        if not wants_reservation:
            await self._answer_availability(query, user_id, session_id, context, event_queue)
            return

        # Task is created and submitted immediately, before the LLM call —
        # matches DigiOpsAgentExecutor's pattern, so a caller using
        # returnImmediately still gets a fast Task ack; the real language
        # understanding (which spot, if any) happens after.
        task = new_task_from_user_message(context.message)
        await event_queue.enqueue_event(task)
        updater = TaskUpdater(
            event_queue=event_queue, task_id=task.id, context_id=task.context_id
        )
        await updater.submit()

        response = await self._call_llm(query, user_id, session_id)
        if response is None:
            await updater.failed(
                message=updater.new_agent_message(
                    parts=[new_text_part('No usable response produced.')]
                )
            )
            return

        spot = find_mentioned_spot(response.reserve_spot_id or '')
        if spot is None:
            # Either the LLM asked a real clarifying question (no clear
            # spot named), or it named something that isn't a real spot —
            # both cases genuinely need more input from the user rather
            # than guessing.
            await updater.requires_input(
                message=updater.new_agent_message(parts=[new_text_part(response.message)])
            )
            return

        on_date = resolve_date(response.reservation_date or 'today')
        await updater.start_work(
            message=updater.new_agent_message(
                parts=[new_text_part(
                    f'Checking spot {spot.spot_id} for {on_date.isoformat()} with facilities...'
                )]
            )
        )

        cancel_signal = asyncio.Event()
        _cancel_signals[task.id] = cancel_signal
        try:
            try:
                await asyncio.wait_for(
                    cancel_signal.wait(), timeout=_CHECK_DELAY_SECONDS
                )
                # Signal fired before the timeout: cancel() already handled
                # the task-state transition, nothing left to do here.
                return
            except asyncio.TimeoutError:
                pass  # Not canceled — proceed to resolve the reservation.

            if not is_free(spot.spot_id, on_date):
                await updater.reject(
                    message=updater.new_agent_message(
                        parts=[new_text_part(
                            f'Spot {spot.spot_id} is already taken on {on_date.isoformat()}.'
                        )]
                    )
                )
                return

            reservation = create_reservation(
                spot.spot_id, on_date, response.employee_name, task.id
            )
            await updater.complete(
                message=updater.new_agent_message(
                    parts=[new_text_part(
                        f'Spot {spot.spot_id} reserved for {reservation.employee_name} on '
                        f'{on_date.isoformat()} (reservation id: {reservation.reservation_id}).'
                    )]
                )
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
    ) -> AgentResponse | None:
        """Runs the real ADK Runner and parses its structured response.
        Returns None if the model produced no final response or the
        response didn't parse as the expected schema."""
        content = types.Content(role='user', parts=[types.Part.from_text(text=query)])
        final_text = None
        async for event in self._runner.run_async(
            user_id=user_id, session_id=session_id, new_message=content
        ):
            if event.is_final_response() and event.content and event.content.parts:
                final_text = event.content.parts[0].text

        if final_text is None:
            return None
        try:
            return AgentResponse.model_validate_json(final_text.strip())
        except ValueError:
            return None

    async def _answer_availability(
        self, query, user_id, session_id, context, event_queue
    ) -> None:
        response = await self._call_llm(query, user_id, session_id)
        reply = response.message if response is not None else (
            'Sorry, I was not able to process that.'
        )
        await event_queue.enqueue_event(
            new_text_message(reply, context_id=context.message.context_id)
        )

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        task = context.current_task
        if task is None:
            return
        signal = _cancel_signals.get(task.id)
        updater = TaskUpdater(
            event_queue=event_queue, task_id=task.id, context_id=task.context_id
        )
        await updater.cancel(
            message=updater.new_agent_message(
                parts=[new_text_part('Reservation request canceled.')]
            )
        )
        if signal is not None:
            signal.set()
