import os
import sys

import uvicorn

from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService

from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
)
from starlette.applications import Starlette

from agent import root_agent
from agent_executor import DigiOpsAgentExecutor

# BIND_HOST is what the server actually listens on; ADVERTISED_HOST is
# what the agent card tells other clients to connect to — different in
# Docker, where the container must bind 0.0.0.0 but advertise the
# Compose service name (see docker-compose.yml), same in local-process
# use (both default to 127.0.0.1).
BIND_HOST = os.getenv('A2A_BIND_HOST', '127.0.0.1')
ADVERTISED_HOST = os.getenv('A2A_ADVERTISED_HOST', '127.0.0.1')
PORT = 8001

if __name__ == '__main__':
    if not os.getenv('ANTHROPIC_API_KEY'):
        print(
            'ANTHROPIC_API_KEY is not set — the agent will boot and serve '
            'its card, but FAQ/ticket/incident handling will fail on the '
            'first real request. See docs/implementation-plan.md Phase 9.',
            file=sys.stderr,
        )

    skills = [
        AgentSkill(
            id='faq-answer',
            name='Answer IT FAQs',
            description='Answers common IT questions — VPN access, password resets, standard hardware.',
            tags=['it', 'faq'],
            examples=['how do I connect to the VPN?'],
        ),
        AgentSkill(
            id='hardware-request',
            name='Request hardware',
            description='Opens and tracks a hardware provisioning ticket.',
            tags=['it', 'ticket'],
            examples=['I need a new laptop charger'],
        ),
        AgentSkill(
            id='incident-investigation',
            name='Investigate an incident',
            description='Investigates a reported IT incident with live status updates.',
            tags=['it', 'incident'],
            examples=['my laptop cannot reach the internal network'],
        ),
    ]

    agent_card = AgentCard(
        name='DigiOps Agent',
        description='WSO2 IT Helpdesk — FAQs, hardware requests, and live incident investigation.',
        version='0.1.0',
        default_input_modes=['text/plain'],
        default_output_modes=['text/plain'],
        capabilities=AgentCapabilities(
            streaming=True,
            push_notifications=False,
            extended_agent_card=False,
        ),
        supported_interfaces=[
            AgentInterface(
                protocol_binding='JSONRPC',
                url=f'http://{ADVERTISED_HOST}:{PORT}',
                protocol_version='1.0',
            )
        ],
        skills=skills,
    )

    runner = Runner(
        app_name=root_agent.name,
        agent=root_agent,
        session_service=InMemorySessionService(),
    )

    request_handler = DefaultRequestHandler(
        agent_executor=DigiOpsAgentExecutor(runner),
        task_store=InMemoryTaskStore(),
        agent_card=agent_card,
    )

    routes = []
    routes.extend(create_agent_card_routes(agent_card))
    routes.extend(create_jsonrpc_routes(request_handler, '/'))

    app = Starlette(routes=routes)
    uvicorn.run(app, host=BIND_HOST, port=PORT)
