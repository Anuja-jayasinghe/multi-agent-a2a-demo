# A2A demo: Operations Desk

One A2A agent, one client that walks the protocol, and one chat service that uses the agent as a tool.
Everything runs locally. The agent and the chat service call Anthropic (Claude Haiku 4.5), so each needs a key.
The client does not need one.

## Requirements

The three packages depend on `ballerina/a2a` 0.1.0 from the local repository, because that version is not released yet. Build it
from [module-ballerina-a2a](https://github.com/ballerina-platform/module-ballerina-a2a) (the `feat/http-json-listener` branch,
pull request #4) and push it once:

```
./gradlew :a2a-native:build
cd ballerina && bal pack && bal push --repository=local
```

## Setup

1. Put your key in `ops-desk-server/Config.toml` and `ops-chat/Config.toml` (copy the `.example` file). Both are git-ignored.
2. Start each program in its own terminal. The chat service connects to the agent on its first request, so the start order does not matter.

```
cd ops-desk-server && bal run        # A2A agent on :9090
cd ops-chat && bal run               # chat service on :8090
cd ops-desk-client && bal run        # prints the protocol lifecycle, then exits
```

## What each program shows

**ops-desk-server** (`agent.bal`, `tools.bal`, `service.bal`)
- The agent logic is an `a2a:AgentExecutor`. It runs an `ai:Agent` and reports through the `a2a:TaskUpdater`.
- The service defines six operations. Streaming is on because both streaming operations exist, push notifications are off
  because none of the push operations do: the card follows the service.
- Open `http://localhost:9090/.well-known/agent-card.json` to show the card the listener served.

**ops-desk-client** (`main.bal`), numbered as it prints
1. Discover: the card, its skills and capabilities.
2. Ask for access without saying why: the task pauses in `TASK_STATE_INPUT_REQUIRED`.
3. Answer on the same task: provisioning takes six seconds, then it completes with an artifact.
4. Stream: status and artifact events arrive as they happen.
5. `getTask` and `listTasks`.
6. Start a task (submitted), look again after two seconds (working), then cancel it (canceled).

**ops-chat** (`agent.bal`, `service.bal`)
- A chat agent behind `ai:Listener`. Its only tool, `askOperationsDesk`, calls the A2A agent through `a2a:HttpClient`.
- If the desk pauses for input, the tool returns the question and the `taskId`, the chat agent asks the user, and the next turn
  continues the same task.

## Chat prompts

Send them to `POST http://localhost:8090/chat` (or the chat panel in WSO2 Integrator) with the same `sessionId`:

```
curl -s -X POST localhost:8090/chat -H 'Content-Type: application/json' \
  -d '{"sessionId": "demo", "message": "Can you get Nimal access to the staging cloud project?"}'
curl -s -X POST localhost:8090/chat -H 'Content-Type: application/json' \
  -d '{"sessionId": "demo", "message": "It is for the load test of the payments release"}'
curl -s -X POST localhost:8090/chat -H 'Content-Type: application/json' \
  -d '{"sessionId": "demo", "message": "What happened to the gateway overnight?"}'
```

Others: "Claim 340 USD for conference travel for Kasun" (asks for the receipt), "Onboarding checklist for Dilini joining the
Identity team on Monday".

## Not covered

Push notifications (they need a webhook receiver), JSON-RPC, and authentication on the listener.
