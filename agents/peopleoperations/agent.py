from collections.abc import AsyncIterable
from typing import Any, Literal

from langchain_anthropic import ChatAnthropic
from langchain_core.messages import AIMessage, ToolMessage
from langgraph.checkpoint.memory import MemorySaver
from langgraph.prebuilt import create_react_agent
from pydantic import BaseModel

from tools import (
    assign_desk,
    check_onboarding_status,
    enroll_benefits,
    escalate_case,
    file_leave_request,
    provision_laptop,
    revoke_desk,
    revoke_laptop,
    terminate_benefits,
)

memory = MemorySaver()

ONBOARDING_TOOLS = {'provision_laptop', 'assign_desk', 'enroll_benefits'}
OFFBOARDING_TOOLS = {'revoke_laptop', 'revoke_desk', 'terminate_benefits'}
# Tool name -> flow kind, for the executor to pick the right staged-wait
# env-var delay (ONBOARDING_STEP_DELAY_SECONDS vs
# OFFBOARDING_STEP_DELAY_SECONDS) without string-matching yielded content.
STAGED_TOOL_FLOW = {name: 'onboarding' for name in ONBOARDING_TOOLS} | {
    name: 'offboarding' for name in OFFBOARDING_TOOLS
}

# Fictional-but-WSO2-styled HR reference facts — no real internal policy or
# figures, consistent, plausible facts the agent can answer policy
# questions from.
_HR_CONTEXT = """
WSO2 People Operations reference facts (for answering policy questions):
- Annual leave: 20 days per year, accrued monthly, carries over up to 5
  unused days into the next year
- Benefits: private health insurance, WFH stipend, annual learning budget
- Onboarding: every new hire needs a laptop provisioned, a desk assigned,
  and enrollment in standard benefits
- Offboarding: every departing employee needs their laptop revoked, their
  desk freed, and their benefits enrollment terminated
"""


class ResponseFormat(BaseModel):
    """Respond to the user in this format."""

    status: Literal['input_required', 'completed', 'error'] = 'input_required'
    message: str


class PeopleOperationsAgent:
    SYSTEM_INSTRUCTION = (
        'You are the WSO2 People Operations (HR) agent. Answer policy '
        'questions directly from the reference facts below.\n\n'
        'When asked to onboard a new hire, call provision_laptop, '
        'assign_desk, and enroll_benefits, in that order, for the named '
        'employee — call each exactly once, never skip one or repeat one; '
        'check the tool calls you already made in this turn before '
        'deciding a step is done.\n\n'
        'When asked to offboard a departing employee, call revoke_laptop, '
        'revoke_desk, and terminate_benefits, in that order, for the named '
        'employee, with the same exactly-once rule.\n\n'
        'When asked about the status of a new hire\'s onboarding, always '
        'call check_onboarding_status with their name for a fresh answer — '
        'never guess or reuse what you found earlier in the conversation.\n\n'
        'When an employee wants to take leave, call file_leave_request with '
        'their name, a start date, an end date, and a short reason. If they '
        'have not given you concrete dates, ask for them — do not invent '
        'dates.\n\n'
        'When asked to escalate a sensitive HR case, call escalate_case with '
        'the employee name and a short summary. It is staff-only and enforces '
        'that itself — if it returns status "denied", report that refusal to '
        'the user plainly and do not claim the case was escalated.\n'
        + _HR_CONTEXT
    )

    FORMAT_INSTRUCTION = (
        'Set response status to input_required if the user needs to provide more '
        'information to complete the request (e.g. missing the employee name for '
        'onboarding, or missing dates for a leave request). Set response status '
        'to error if there is an error while processing the request. Set response '
        'status to completed once the question is answered, the onboarding/'
        'offboarding steps are done, or the leave request is filed. The message '
        'field is the ONLY thing the user will ever see — put the real answer '
        'or confirmation in it in full.'
    )

    def __init__(self) -> None:
        self.model = ChatAnthropic(model='claude-sonnet-4-5')
        self.tools = [
            provision_laptop,
            assign_desk,
            enroll_benefits,
            revoke_laptop,
            revoke_desk,
            terminate_benefits,
            check_onboarding_status,
            file_leave_request,
            escalate_case,
        ]
        self.graph = create_react_agent(
            self.model,
            tools=self.tools,
            checkpointer=memory,
            prompt=self.SYSTEM_INSTRUCTION,
            response_format=(self.FORMAT_INSTRUCTION, ResponseFormat),
        )

    async def stream(self, query: str, context_id: str) -> AsyncIterable[dict[str, Any]]:
        inputs = {'messages': [('user', query)]}
        config = {'configurable': {'thread_id': context_id}}
        called_tools: set[str] = set()

        async for item in self.graph.astream(inputs, config, stream_mode='values'):
            message = item['messages'][-1]
            if (
                isinstance(message, AIMessage)
                and message.tool_calls
                and len(message.tool_calls) > 0
            ):
                # Claude can return several tool_calls on one AIMessage
                # (parallel tool use) -- e.g. all 3 onboarding steps in one
                # turn. Narrate and track every one, not just the first, or
                # both the progress narration and the completeness check
                # below silently miss real tool calls that did happen.
                for tool_call in message.tool_calls:
                    tool_name = tool_call['name']
                    called_tools.add(tool_name)
                    yield {
                        'is_task_complete': False,
                        'require_user_input': False,
                        'content': f'Running step: {tool_name}...',
                        'tool_name': tool_name,
                    }
            elif isinstance(message, ToolMessage):
                yield {
                    'is_task_complete': False,
                    'require_user_input': False,
                    'content': 'Step complete.',
                    'tool_name': None,
                }

        yield self.get_agent_response(config, called_tools)

    def get_agent_response(self, config: dict, called_tools: set[str]) -> dict[str, Any]:
        current_state = self.graph.get_state(config)
        structured_response = current_state.values.get('structured_response')
        if structured_response and isinstance(structured_response, ResponseFormat):
            if structured_response.status == 'completed':
                # Executor-side validation, same defensive spirit as
                # Parking's mentioned-spot check: don't just trust the
                # LLM's own claim that a multi-step on/offboarding
                # sequence finished — verify every real tool in that
                # sequence was actually called this turn first.
                missing = _incomplete_sequence(called_tools)
                if missing is not None:
                    return {
                        'is_task_complete': False,
                        'require_user_input': True,
                        'content': (
                            f'{structured_response.message}\n\n'
                            '(Not actually finished yet — still missing: '
                            f'{", ".join(sorted(missing))}.)'
                        ),
                    }
                return {
                    'is_task_complete': True,
                    'require_user_input': False,
                    'content': structured_response.message,
                }
            if structured_response.status in ('input_required', 'error'):
                return {
                    'is_task_complete': False,
                    'require_user_input': True,
                    'content': structured_response.message,
                }

        return {
            'is_task_complete': False,
            'require_user_input': True,
            'content': 'Unable to process the request at the moment. Please try again.',
        }


def _incomplete_sequence(called_tools: set[str]) -> set[str] | None:
    """Returns the still-missing tool names if called_tools shows a partial
    onboarding or offboarding sequence, else None."""
    for sequence in (ONBOARDING_TOOLS, OFFBOARDING_TOOLS):
        touched = called_tools & sequence
        if touched and touched != sequence:
            return sequence - touched
    return None
