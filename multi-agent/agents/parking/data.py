"""Mock parking data for the WSO2 Colombo HQ office car park.

Real, public, harmless fact used for flavor (WSO2's HQ is in Colombo); the
spots, occupancy, and reservations themselves are entirely fictional.

Reservations are day-scoped: a spot isn't globally "free" or "taken", it's
free or taken *on a given date* -- "reserve me a spot tomorrow" and
"reserve me a spot today" can now genuinely mean different things.
"""

import uuid
from dataclasses import dataclass
from datetime import date, timedelta


@dataclass
class SpotInfo:
    spot_id: str
    level: str


SPOTS: dict[str, SpotInfo] = {
    s.spot_id: s
    for s in [
        SpotInfo('A01', 'Level 1'),
        SpotInfo('A02', 'Level 1'),
        SpotInfo('A03', 'Level 1'),
        SpotInfo('A04', 'Level 1'),
        SpotInfo('B01', 'Level 2'),
        SpotInfo('B02', 'Level 2'),
        SpotInfo('B03', 'Level 2'),
        SpotInfo('B04', 'Level 2'),
    ]
}


@dataclass
class Reservation:
    reservation_id: str
    spot_id: str
    reservation_date: date
    employee_name: str
    task_id: str | None
    status: str = 'active'  # active | canceled


_RESERVATIONS: dict[str, Reservation] = {}


def _seed_preset_reservations() -> None:
    # A02 and B02 start pre-booked for today, same as the old data always
    # had them permanently taken -- now day-scoped instead of permanent, so
    # they're free again from tomorrow on.
    for spot_id in ('A02', 'B02'):
        reservation_id = uuid.uuid4().hex[:8]
        _RESERVATIONS[reservation_id] = Reservation(
            reservation_id=reservation_id,
            spot_id=spot_id,
            reservation_date=date.today(),
            employee_name='(pre-booked)',
            task_id=None,
        )


_seed_preset_reservations()


def resolve_date(date_text: str) -> date:
    """Resolves "today"/"tomorrow"/an ISO "YYYY-MM-DD" string into a real
    date. Falls back to today for anything else, rather than failing the
    whole request over a date-format quirk."""
    normalized = date_text.strip().lower()
    if normalized in ('', 'today'):
        return date.today()
    if normalized == 'tomorrow':
        return date.today() + timedelta(days=1)
    try:
        return date.fromisoformat(date_text.strip())
    except ValueError:
        return date.today()


def find_mentioned_spot(text: str) -> SpotInfo | None:
    """Finds the first known spot id mentioned in free-form text, case-insensitive."""
    upper = text.upper()
    for spot_id, spot in SPOTS.items():
        if spot_id in upper:
            return spot
    return None


def _active_reservation(spot_id: str, on_date: date) -> Reservation | None:
    for reservation in _RESERVATIONS.values():
        if (
            reservation.spot_id == spot_id
            and reservation.reservation_date == on_date
            and reservation.status == 'active'
        ):
            return reservation
    return None


def is_free(spot_id: str, on_date: date) -> bool:
    return _active_reservation(spot_id, on_date) is None


def reservation_holder(spot_id: str, on_date: date) -> str | None:
    reservation = _active_reservation(spot_id, on_date)
    return reservation.employee_name if reservation is not None else None


def free_spots_on(on_date: date) -> list[SpotInfo]:
    return [s for s in SPOTS.values() if is_free(s.spot_id, on_date)]


def create_reservation(
    spot_id: str, on_date: date, employee_name: str, task_id: str
) -> Reservation:
    reservation_id = uuid.uuid4().hex[:8]
    reservation = Reservation(
        reservation_id=reservation_id,
        spot_id=spot_id,
        reservation_date=on_date,
        employee_name=employee_name,
        task_id=task_id,
    )
    _RESERVATIONS[reservation_id] = reservation
    return reservation


def my_reservations(employee_name: str) -> list[Reservation]:
    return [
        r
        for r in _RESERVATIONS.values()
        if r.employee_name == employee_name and r.status == 'active'
    ]


def cancel_reservation_by_id(reservation_id: str) -> Reservation | None:
    """Real cancel for an already-completed reservation -- distinct from
    cancelTask, which only works while the reservation task is still
    pending. Returns None if the id is unknown or already canceled."""
    reservation = _RESERVATIONS.get(reservation_id)
    if reservation is None or reservation.status != 'active':
        return None
    reservation.status = 'canceled'
    return reservation
