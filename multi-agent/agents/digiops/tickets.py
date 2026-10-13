"""Mock hardware-ticket store for the DigiOps agent.

Tool functions called by the real LLM (see agent.py) — the actions are
genuine (they mutate real in-memory state the agent lifecycle depends on),
the persistence layer is just in-memory for the demo.
"""

import uuid

_TICKETS: dict[str, dict] = {}

# Standard hardware catalog fulfills fast, no manager-approval wait —
# matching what the agent's own prompt already tells the user. Anything
# else is a genuine over-catalog request that needs staged approval (see
# agent_executor.py's _run_provisioning_flow).
STANDARD_CATALOG = ('laptop', 'monitor', 'docking station', 'headset')


_FILLER_PREFIXES = ('a new ', 'a ', 'an ', 'the ', 'new ')


def _is_standard_catalog(item: str) -> bool:
    # Exact match after stripping filler words, not a substring check --
    # "laptop charger" or "monitor stand" must NOT match just because
    # "laptop"/"monitor" appears inside them; those are real accessories
    # outside the catalog, not the catalog item itself.
    normalized = item.strip().lower()
    for prefix in _FILLER_PREFIXES:
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix):]
            break
    return normalized in STANDARD_CATALOG


def create_ticket(item: str, raised_by: str, severity: str = 'low') -> dict:
    """Opens a hardware ticket.

    Args:
        item: A short description of the requested hardware, e.g. "laptop charger".
        raised_by: The real name of the employee raising the ticket.
        severity: How urgent the request is -- "low", "medium", or "high".
    """
    ticket_id = str(uuid.uuid4())[:8]
    over_catalog = not _is_standard_catalog(item)
    _TICKETS[ticket_id] = {
        'item': item,
        'status': 'pending_approval' if over_catalog else 'open',
        'raised_by': raised_by,
        'severity': severity,
        'over_catalog': over_catalog,
    }
    return {'ticket_id': ticket_id, **_TICKETS[ticket_id]}


def get_ticket(ticket_id: str) -> dict:
    """Looks up the status of an existing hardware ticket.

    Args:
        ticket_id: The ticket identifier returned by create_ticket.
    """
    ticket = _TICKETS.get(ticket_id)
    if ticket is None:
        return {'error': f'no ticket found with id {ticket_id}'}
    return {'ticket_id': ticket_id, **ticket}


def list_my_tickets(employee_name: str) -> dict:
    """Lists all real hardware tickets raised by a named employee.

    Args:
        employee_name: The employee's name.
    """
    mine = [
        {'ticket_id': ticket_id, **ticket}
        for ticket_id, ticket in _TICKETS.items()
        if ticket['raised_by'] == employee_name
    ]
    return {'employee_name': employee_name, 'tickets': mine}


def close_ticket(ticket_id: str) -> dict:
    """Closes a real hardware ticket, e.g. once the employee confirms
    they've received the item.

    Args:
        ticket_id: The ticket identifier returned by create_ticket.
    """
    ticket = _TICKETS.get(ticket_id)
    if ticket is None:
        return {'error': f'no ticket found with id {ticket_id}'}
    ticket['status'] = 'closed'
    return {'ticket_id': ticket_id, **ticket}


def mark_fulfilled(ticket_id: str) -> None:
    """Executor-only (not an LLM tool): flips a ticket from open/
    pending_approval to fulfilled once its real provisioning flow — staged
    or fast-path — has actually finished."""
    ticket = _TICKETS.get(ticket_id)
    if ticket is not None:
        ticket['status'] = 'fulfilled'
