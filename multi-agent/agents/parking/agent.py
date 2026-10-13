from typing import Literal

from google.adk.agents import LlmAgent
from google.adk.models.anthropic_llm import AnthropicLlm
from pydantic import BaseModel, Field

from data import (
    cancel_reservation_by_id,
    find_mentioned_spot,
    free_spots_on,
    is_free,
    my_reservations,
    reservation_holder,
    resolve_date,
)


def check_spot(spot_id: str, reservation_date: str = 'today') -> str:
    """Checks whether a specific WSO2 Colombo HQ parking spot is free on a
    given date, and who holds it if it's taken.

    Args:
        spot_id: The spot's id, e.g. "A01".
        reservation_date: "today", "tomorrow", or an ISO date "YYYY-MM-DD".
            Defaults to today.
    """
    spot = find_mentioned_spot(spot_id)
    if spot is None:
        return f'"{spot_id}" is not a known spot id.'
    on_date = resolve_date(reservation_date)
    if is_free(spot.spot_id, on_date):
        return f'Spot {spot.spot_id} ({spot.level}) is free on {on_date.isoformat()}.'
    holder = reservation_holder(spot.spot_id, on_date)
    holder_note = f', reserved by {holder}' if holder else ''
    return f'Spot {spot.spot_id} ({spot.level}) is taken on {on_date.isoformat()}{holder_note}.'


def list_free_spots(reservation_date: str = 'today') -> str:
    """Lists every WSO2 Colombo HQ parking spot free on a given date.

    Args:
        reservation_date: "today", "tomorrow", or an ISO date "YYYY-MM-DD".
            Defaults to today.
    """
    on_date = resolve_date(reservation_date)
    free = [f'{s.spot_id} ({s.level})' for s in free_spots_on(on_date)]
    if not free:
        return f'No spots are free on {on_date.isoformat()}.'
    return f'Free on {on_date.isoformat()}: ' + ', '.join(free)


def list_my_reservations(employee_name: str) -> str:
    """Lists every real active reservation held by a named employee, across
    all dates.

    Args:
        employee_name: The employee's real name.
    """
    mine = my_reservations(employee_name)
    if not mine:
        return f'{employee_name} has no active reservations.'
    lines = [
        f'{r.reservation_id}: spot {r.spot_id} on {r.reservation_date.isoformat()}'
        for r in mine
    ]
    return '; '.join(lines)


def cancel_reservation(reservation_id: str) -> str:
    """Cancels a real, already-completed reservation by its reservation id
    (from list_my_reservations), freeing the spot back up for that date.
    This is for a reservation that already finished being made -- a
    reservation still being processed is canceled via the task's own
    cancelTask instead, not this tool.

    Args:
        reservation_id: The reservation id, e.g. from list_my_reservations.
    """
    reservation = cancel_reservation_by_id(reservation_id)
    if reservation is None:
        return f'No active reservation found with id {reservation_id}.'
    return (
        f'Reservation {reservation_id} for spot {reservation.spot_id} on '
        f'{reservation.reservation_date.isoformat()} has been canceled.'
    )


class AgentResponse(BaseModel):
    """Structured reply the LLM must produce.

    Attributes:
        message: The reply text for the user.
        status: completed | input-required | failed.
        reserve_spot_id: Set only when the user clearly wants to reserve
            this exact spot and has given their name; left null for
            availability questions or when more information is needed
            before a reservation can proceed.
        employee_name: The requester's real name for a reservation. Only
            meaningful alongside reserve_spot_id.
        reservation_date: The date to reserve for -- "today", "tomorrow",
            or an ISO date -- only meaningful alongside reserve_spot_id.
            Defaults to "today" when the user didn't specify one.
    """

    message: str = Field(description='Reply text for the user')
    status: Literal['completed', 'input-required', 'failed'] = Field(
        description='Status of the agent response'
    )
    reserve_spot_id: str | None = Field(
        default=None,
        description=(
            'Set only when the user clearly wants to reserve this exact '
            'known spot id AND has given their name. Leave null for '
            'availability questions, or when a reservation was requested '
            'but no single clear spot id or no name was given -- ask a '
            'clarifying question instead and leave this null.'
        ),
    )
    employee_name: str | None = Field(
        default=None,
        description=(
            "The requester's real name, only set alongside reserve_spot_id "
            'when both the spot id and the name are known.'
        ),
    )
    reservation_date: str | None = Field(
        default=None,
        description=(
            'The date to reserve for: "today", "tomorrow", or an ISO date '
            '"YYYY-MM-DD" -- only set alongside reserve_spot_id. Leave '
            'null (defaults to today) if the user did not mention a date.'
        ),
    )


root_agent = LlmAgent(
    name='parking_agent',
    model=AnthropicLlm(model='claude-opus-4-8'),
    description='WSO2 Colombo HQ Parking Manager agent — availability lookups and reservations.',
    instruction=(
        'You are the WSO2 Colombo HQ Parking Manager agent. Reservations '
        'are day-scoped -- a spot free today may be taken tomorrow and '
        'vice versa, so always account for which date is being asked '
        'about.\n\n'
        'For an availability question (including general ones like "is '
        'anything free?"), call list_free_spots or check_spot as needed, '
        'passing the date the user means (default to today if they did not '
        'say) -- answer from the real result, never guess at spot state '
        'yourself.\n\n'
        'To list an employee\'s own reservations, call list_my_reservations '
        'with their name. To cancel a reservation that has already been '
        'made (as opposed to one still being processed), call '
        'cancel_reservation with its reservation id.\n\n'
        'For a NEW reservation request, your job is to decide which single '
        'spot id, which date, and whose real name -- do NOT call check_spot '
        'or list_free_spots for a reservation request, and do not decide or '
        'comment on whether that spot is actually free on that date; a '
        'separate real system checks that and will report back if it is '
        'taken. Every real reservation is tied to a real employee, so if '
        'they have not told you their name yet, ask for it before '
        'reserving anything -- do not reserve a spot without a name, and '
        'do not invent or assume one. If they name one real spot id '
        'clearly AND have given their name, set reserve_spot_id, '
        'employee_name, reservation_date (default today), and status to '
        '"completed" regardless of whether you think the spot might '
        'already be taken on that date. If they ask to reserve a spot but '
        'do not give a clear single spot id (e.g. "reserve me a spot on '
        'level 2"), or have not given their name yet, ask a real '
        'clarifying question for whichever is missing and leave '
        'reserve_spot_id/employee_name null -- do not guess or pick one '
        'for them.\n\n'
        'Use "completed" once the request has been fully answered, '
        '"input-required" when you need more information from the user, '
        'and "failed" only if a tool call errored.'
    ),
    tools=[check_spot, list_free_spots, list_my_reservations, cancel_reservation],
    output_schema=AgentResponse,
)
