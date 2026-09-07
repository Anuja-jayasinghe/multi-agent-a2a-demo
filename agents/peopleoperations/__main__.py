import os

import uvicorn

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
    HTTPAuthSecurityScheme,
    SecurityRequirement,
    SecurityScheme,
)
from starlette.applications import Starlette

from agent_executor import PeopleOperationsAgentExecutor
from auth import BearerTokenContextBuilder, extended_card_modifier

# BIND_HOST is what the server actually listens on; ADVERTISED_HOST is
# what the agent card tells other clients to connect to — different in
# Docker, where the container must bind 0.0.0.0 but advertise the
# Compose service name (see docker-compose.yml), same in local-process
# use (both default to 127.0.0.1).
BIND_HOST = os.getenv('A2A_BIND_HOST', '127.0.0.1')
ADVERTISED_HOST = os.getenv('A2A_ADVERTISED_HOST', '127.0.0.1')
PORT = 8002

STAFF_SCHEME = 'bearer-staff'

# The credential BearerTokenContextBuilder (auth.py) actually checks, now
# declared rather than left as out-of-band knowledge. Without this a client
# can see that case-escalation exists but has no way to learn what unlocks
# it -- the A2A spec's answer to "which credential?" is exactly this
# securitySchemes/securityRequirements pair, and serving neither forces
# callers to guess.
SECURITY_SCHEMES = {
    STAFF_SCHEME: SecurityScheme(
        http_auth_security_scheme=HTTPAuthSecurityScheme(
            scheme='Bearer',
            description='Staff bearer token. Unlocks the extended card and its staff-only skills.',
        )
    )
}

# Card-level: this agent understands the staff token on every request --
# BearerTokenContextBuilder runs for all JSON-RPC routes, not just the
# extended-card one. It is not a hard gate; the public skills answer
# unauthenticated, and the extended card downgrades rather than rejecting.
STAFF_REQUIREMENT = [SecurityRequirement(schemes={STAFF_SCHEME: {'list': []}})]

if __name__ == '__main__':
    skills = [
        AgentSkill(
            id='policy-qa',
            name='Answer HR policy questions',
            description='Answers common HR policy questions — leave, benefits.',
            tags=['hr', 'policy'],
            examples=['how many annual leave days do I have?'],
        ),
        AgentSkill(
            id='onboarding',
            name='Run onboarding checklist',
            description='Runs a new-hire onboarding checklist with live progress updates.',
            tags=['hr', 'onboarding'],
            examples=['start my onboarding checklist'],
        ),
    ]

    agent_card = AgentCard(
        name='PeopleOperations Agent',
        description='WSO2 People Operations — policy Q&A and onboarding.',
        version='0.1.0',
        default_input_modes=['text/plain'],
        default_output_modes=['text/plain'],
        capabilities=AgentCapabilities(
            streaming=True,
            push_notifications=False,
            extended_agent_card=True,
        ),
        supported_interfaces=[
            AgentInterface(
                protocol_binding='JSONRPC',
                url=f'http://{ADVERTISED_HOST}:{PORT}',
                protocol_version='1.0',
            )
        ],
        security_schemes=SECURITY_SCHEMES,
        security_requirements=STAFF_REQUIREMENT,
        skills=skills,
    )

    extended_skills = [
        *skills,
        AgentSkill(
            id='case-escalation',
            name='Escalate an HR case',
            description='Escalates a sensitive HR case for staff follow-up. Staff-only.',
            tags=['hr', 'staff-only'],
            examples=['escalate this grievance to a case manager'],
            # Skill-level, not just card-level: this is the one skill that
            # genuinely needs the staff token, so a client can discover
            # that from the card instead of being told out of band.
            security_requirements=STAFF_REQUIREMENT,
        ),
    ]
    extended_agent_card = AgentCard(
        name='PeopleOperations Agent (Staff)',
        description='WSO2 People Operations — policy Q&A, onboarding, and staff-only case escalation.',
        version='0.1.0',
        default_input_modes=['text/plain'],
        default_output_modes=['text/plain'],
        capabilities=AgentCapabilities(
            streaming=True,
            push_notifications=False,
            extended_agent_card=True,
        ),
        supported_interfaces=[
            AgentInterface(
                protocol_binding='JSONRPC',
                url=f'http://{ADVERTISED_HOST}:{PORT}',
                protocol_version='1.0',
            )
        ],
        security_schemes=SECURITY_SCHEMES,
        security_requirements=STAFF_REQUIREMENT,
        skills=extended_skills,
    )

    request_handler = DefaultRequestHandler(
        agent_executor=PeopleOperationsAgentExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=agent_card,
        extended_agent_card=extended_agent_card,
        extended_card_modifier=extended_card_modifier,
    )

    routes = []
    routes.extend(create_agent_card_routes(agent_card))
    routes.extend(
        create_jsonrpc_routes(
            request_handler, '/', context_builder=BearerTokenContextBuilder()
        )
    )

    app = Starlette(routes=routes)
    uvicorn.run(app, host=BIND_HOST, port=PORT)
