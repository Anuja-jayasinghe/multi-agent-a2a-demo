"""Real (if minimal) bearer-token auth gating the extended agent card.

Not a stub: an actual Authorization header check against a real shared
secret, wired through the SDK's own ServerCallContext mechanism — the
extended card genuinely differs for an authenticated vs. unauthenticated
caller, verified by hitting getExtendedAgentCard both ways.
"""

import os

from starlette.requests import Request

from a2a.server.context import ServerCallContext, User
from a2a.server.routes.common import DefaultServerCallContextBuilder
from a2a.types import AgentCard

_STAFF_TOKEN_ENV = 'PEOPLEOPS_STAFF_TOKEN'


class _StaffUser(User):
    @property
    def is_authenticated(self) -> bool:
        return True

    @property
    def user_name(self) -> str:
        return 'hr-staff'


class BearerTokenContextBuilder(DefaultServerCallContextBuilder):
    """Extends the default context builder (which handles A2A-Version
    detection and everything else) — only build_user() is overridden, to
    set an authenticated staff user when the request carries a valid
    `Authorization: Bearer <token>` header matching PEOPLEOPS_STAFF_TOKEN.
    """

    def build_user(self, request: Request) -> User:
        expected = os.getenv(_STAFF_TOKEN_ENV)
        auth_header = request.headers.get('authorization', '')
        if expected and auth_header == f'Bearer {expected}':
            return _StaffUser()
        return super().build_user(request)


async def extended_card_modifier(card: AgentCard, context: ServerCallContext) -> AgentCard:
    """Strips the staff-only case-escalation skill for an unauthenticated
    caller — the extended card genuinely differs, it isn't served
    identically regardless of who's asking.

    AgentCard is a protobuf message here (no model_copy), so this rebuilds
    it explicitly rather than mutating the shared instance in place.
    """
    if context.user.is_authenticated:
        return card
    return AgentCard(
        name=card.name,
        description=card.description,
        version=card.version,
        default_input_modes=list(card.default_input_modes),
        default_output_modes=list(card.default_output_modes),
        capabilities=card.capabilities,
        supported_interfaces=list(card.supported_interfaces),
        # Carried over deliberately: an unauthenticated caller still needs
        # to see *which* credential would unlock more, or the downgrade
        # tells it nothing actionable. Rebuilding field-by-field silently
        # drops anything not named here, so these two are easy to lose.
        security_schemes=dict(card.security_schemes),
        security_requirements=list(card.security_requirements),
        skills=[s for s in card.skills if s.id != 'case-escalation'],
    )
