"""Real onboarding/offboarding tool functions the LangGraph agent calls —
each call is a genuine state mutation (in-memory HR checklists and leave
requests), not canned text. Calling them in sequence during onboarding/
offboarding is what produces the LLM's own progress narration in the
streaming flow (see agent.py's stream()).
"""

import uuid

from langchain_core.tools import tool

from auth import staff_authenticated

_ONBOARDING_CHECKLISTS: dict[str, dict[str, bool]] = {}
_OFFBOARDING_CHECKLISTS: dict[str, dict[str, bool]] = {}
_LEAVE_REQUESTS: dict[str, dict] = {}
_ESCALATED_CASES: dict[str, dict] = {}


@tool
def provision_laptop(employee_name: str) -> dict:
    """Provisions a laptop for a new hire.

    Args:
        employee_name: The new hire's name.
    """
    checklist = _ONBOARDING_CHECKLISTS.setdefault(employee_name, {})
    checklist['laptop'] = True
    return {'step': 'laptop', 'done': True}


@tool
def assign_desk(employee_name: str) -> dict:
    """Assigns a desk to a new hire.

    Args:
        employee_name: The new hire's name.
    """
    checklist = _ONBOARDING_CHECKLISTS.setdefault(employee_name, {})
    checklist['desk'] = True
    return {'step': 'desk', 'done': True}


@tool
def enroll_benefits(employee_name: str) -> dict:
    """Enrolls a new hire in standard benefits.

    Args:
        employee_name: The new hire's name.
    """
    checklist = _ONBOARDING_CHECKLISTS.setdefault(employee_name, {})
    checklist['benefits'] = True
    return {'step': 'benefits', 'done': True}


@tool
def check_onboarding_status(employee_name: str) -> dict:
    """Looks up the real onboarding checklist state for a named employee.

    Args:
        employee_name: The employee's name.
    """
    checklist = _ONBOARDING_CHECKLISTS.get(employee_name)
    if checklist is None:
        return {'employee_name': employee_name, 'started': False}
    return {
        'employee_name': employee_name,
        'started': True,
        'laptop': checklist.get('laptop', False),
        'desk': checklist.get('desk', False),
        'benefits': checklist.get('benefits', False),
    }


@tool
def revoke_laptop(employee_name: str) -> dict:
    """Revokes a departing employee's laptop.

    Args:
        employee_name: The departing employee's name.
    """
    checklist = _OFFBOARDING_CHECKLISTS.setdefault(employee_name, {})
    checklist['laptop'] = True
    return {'step': 'laptop', 'done': True}


@tool
def revoke_desk(employee_name: str) -> dict:
    """Frees a departing employee's desk.

    Args:
        employee_name: The departing employee's name.
    """
    checklist = _OFFBOARDING_CHECKLISTS.setdefault(employee_name, {})
    checklist['desk'] = True
    return {'step': 'desk', 'done': True}


@tool
def terminate_benefits(employee_name: str) -> dict:
    """Terminates a departing employee's benefits enrollment.

    Args:
        employee_name: The departing employee's name.
    """
    checklist = _OFFBOARDING_CHECKLISTS.setdefault(employee_name, {})
    checklist['benefits'] = True
    return {'step': 'benefits', 'done': True}


@tool
def file_leave_request(employee_name: str, start_date: str, end_date: str, reason: str) -> dict:
    """Files a real leave request for an employee.

    Args:
        employee_name: The employee's name.
        start_date: First day of leave, e.g. "2026-09-01".
        end_date: Last day of leave, e.g. "2026-09-03".
        reason: Short reason for the leave.
    """
    request_id = uuid.uuid4().hex[:8]
    _LEAVE_REQUESTS[request_id] = {
        'employee_name': employee_name,
        'start_date': start_date,
        'end_date': end_date,
        'reason': reason,
        'status': 'approved',
    }
    return {'request_id': request_id, 'status': 'approved'}


@tool
def escalate_case(employee_name: str, summary: str) -> dict:
    """Escalates a sensitive HR case to a human case manager. Staff-only.

    Args:
        employee_name: The employee the case concerns.
        summary: Short description of what needs escalating.
    """
    # The real gate. Card-level gating only controls whether this skill is
    # *visible*; the A2A spec (section 13.1) requires servers to authorize
    # every request, so visibility alone must not be what protects it.
    # Anyone who knows the skill exists can ask for it, so the check has to
    # live here, at the action.
    if not staff_authenticated.get():
        return {
            'status': 'denied',
            'reason': (
                'Case escalation is staff-only and this request carried no '
                'valid staff token.'
            ),
        }
    case_id = uuid.uuid4().hex[:8]
    _ESCALATED_CASES[case_id] = {
        'employee_name': employee_name,
        'summary': summary,
        'status': 'escalated',
    }
    return {'case_id': case_id, 'status': 'escalated'}
