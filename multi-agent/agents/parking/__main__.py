import os
import sys

import httpx
import uvicorn

from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_rest_routes
from a2a.server.tasks import (
    BasePushNotificationSender,
    InMemoryPushNotificationConfigStore,
    InMemoryTaskStore,
)
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
)
from starlette.applications import Starlette

from agent import root_agent
from agent_executor import ParkingAgentExecutor

# BIND_HOST is what the server actually listens on; ADVERTISED_HOST is
# what the agent card tells other clients to connect to — different in
# Docker, where the container must bind 0.0.0.0 but advertise the
# Compose service name (see docker-compose.yml), same in local-process
# use (both default to 127.0.0.1).
BIND_HOST = os.getenv('A2A_BIND_HOST', '127.0.0.1')
ADVERTISED_HOST = os.getenv('A2A_ADVERTISED_HOST', '127.0.0.1')
PORT = 8000

if __name__ == '__main__':
    if not os.getenv('ANTHROPIC_API_KEY'):
        print(
            'ANTHROPIC_API_KEY is not set — the agent will boot and serve '
            'its card, but availability/reservation handling will fail on '
            'the first real request. See docs/implementation-plan.md Phase 9.',
            file=sys.stderr,
        )

    skills = [
        AgentSkill(
            id='check-availability',
            name='Check parking availability',
            description='Look up whether a given office parking spot is currently free.',
            tags=['parking'],
            examples=['is spot A01 free today?'],
        ),
        AgentSkill(
            id='reserve-spot',
            name='Reserve a parking spot',
            description='Reserve a specific office parking spot.',
            tags=['parking'],
            examples=['reserve spot A01'],
        ),
        AgentSkill(
            id='cancel-reservation',
            name='Cancel a reservation',
            description='Cancel an in-progress parking reservation.',
            tags=['parking'],
            examples=['cancel my reservation for spot A01'],
        ),
    ]

    agent_card = AgentCard(
        name='Parking Manager Agent',
        description='Look up parking availability and manage reservations for WSO2 office parking.',
        version='0.1.0',
        default_input_modes=['text/plain'],
        default_output_modes=['text/plain'],
        capabilities=AgentCapabilities(
            streaming=False,
            push_notifications=True,
            extended_agent_card=False,
        ),
        supported_interfaces=[
            AgentInterface(
                protocol_binding='HTTP+JSON',
                url=f'http://{ADVERTISED_HOST}:{PORT}',
                protocol_version='1.0',
            )
        ],
        skills=skills,
    )

    push_config_store = InMemoryPushNotificationConfigStore()
    push_sender = BasePushNotificationSender(
        httpx_client=httpx.AsyncClient(), config_store=push_config_store
    )

    runner = Runner(
        app_name=root_agent.name,
        agent=root_agent,
        session_service=InMemorySessionService(),
    )

    request_handler = DefaultRequestHandler(
        agent_executor=ParkingAgentExecutor(runner),
        task_store=InMemoryTaskStore(),
        agent_card=agent_card,
        push_config_store=push_config_store,
        push_sender=push_sender,
    )

    routes = []
    routes.extend(create_agent_card_routes(agent_card))
    routes.extend(create_rest_routes(request_handler))

    app = Starlette(routes=routes)
    uvicorn.run(app, host=BIND_HOST, port=PORT)
