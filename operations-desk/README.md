# A2A demo: Operations Desk

One A2A agent and one chat service. The chat service is both an A2A client and a Ballerina AI chat agent: it calls the
agent as a tool from a conversation, and it exposes the whole task lifecycle as plain HTTP endpoints you can curl.
Everything runs locally. Both programs call Anthropic (Claude Haiku 4.5), so each needs a key.

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
cd ops-chat && bal run               # chat service and lifecycle endpoints on :8090
```

## What each program shows

**ops-desk-server** (`agent.bal`, `tools.bal`, `service.bal`)
- The agent logic is an `a2a:AgentExecutor`. It runs an `ai:Agent` and reports through the `a2a:TaskUpdater`.
- The service defines six operations. Streaming is on because both streaming operations exist, push notifications are off
  because none of the push operations do: the card follows the service.
- Open `http://localhost:9090/.well-known/agent-card.json` to show the card the listener served.

**ops-chat** (`desk.bal`, `agent.bal`, `service.bal`, `lifecycle.bal`), one A2A client with two front doors on port 8090
- `desk.bal`: the shared `a2a:HttpClient` to the agent, created on first use so the start order does not matter.
- `agent.bal` and `service.bal`: a chat agent behind `ai:Listener`, at `POST /chat`. Its only tool, `askOperationsDesk`, calls the
  A2A agent. If the desk pauses for input, the tool returns the question and the `taskId`, the chat agent asks the user, and the
  next turn continues the same task. The WSO2 Integrator chat panel talks to this.
- `lifecycle.bal`: the same client as HTTP resources under `/lifecycle`, with no model in between. See the walkthrough below.

## Lifecycle walkthrough (curl, or Try it in WSO2 Integrator)

```
B=localhost:8090/lifecycle; J='Content-Type: application/json'

curl -s $B/card                                                   # 1. discover: skills and capabilities

curl -s -X POST $B/send -H "$J" \
  -d '{"message": "Give Nimal access to the staging cloud project"}'   # 2. task pauses: TASK_STATE_INPUT_REQUIRED

curl -s -X POST $B/send -H "$J" \
  -d '{"message": "It is for the load test of the payments release", "taskId": "<id from step 2>"}'
                                                                  # 3. same task, completes with an artifact after ~6 s

curl -s -N -X POST $B/stream -H "$J" \
  -d '{"message": "What happened to the gateway overnight?"}'     # 4. server-sent events: status and artifact updates

curl -s $B/tasks                                                  # 5. listTasks
curl -s $B/tasks/<id>                                             #    getTask

curl -s -X POST $B/send -H "$J" -d '{"message": "Give Kasun access to the vpn. The reason is that he joins the on-call rotation on Monday", "returnImmediately": true}'
curl -s $B/tasks/<id>                                             # 6. working
curl -s -X POST $B/tasks/<id>/cancel                              #    canceled
```

An unknown task id returns 404.

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
