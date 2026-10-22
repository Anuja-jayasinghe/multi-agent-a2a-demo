# A2A demo: Operations Desk

Two agents talking over A2A. The Operations Desk is an A2A agent; the chat service is a Ballerina AI agent that uses it as an A2A
client through tools, and decides for itself when to discover the desk, send a request, wait, check, list or cancel a task.
Everything runs locally. Both programs call Anthropic (Claude Haiku 4.5), so each needs a key.

## Requirements

Both packages depend on `ballerina/a2a` 0.1.0 from the local repository, because that version is not released yet. Build it
from [module-ballerina-a2a](https://github.com/ballerina-platform/module-ballerina-a2a) (the `feat/http-json-listener` branch,
pull request #4) and push it once:

```
./gradlew :a2a-native:build
cd ballerina && bal pack && bal push --repository=local
```

## Setup

1. Copy `example.env` to `.env` and put your Anthropic key in it. `.env` is git-ignored. Both agents read the key from the
   environment (`BAL_CONFIG_VAR_ANTHROPICAPIKEY` fills the `anthropicApiKey` configurable), so there is no `Config.toml` to keep in sync.
2. Start each program in its own terminal from this folder. Start the desk first: the chat service reads its agent card on startup.

```
set -a; source .env; set +a          # once per terminal
cd ops-desk-server && bal run        # A2A agent on :9090
cd ops-chat && bal run               # agent-backed A2A client (chat service) on :8090
```

## What each program shows

**ops-desk-server** (`agent.bal`, `tools.bal`, `service.bal`)
- The agent logic is an `a2a:AgentExecutor`. It runs an `ai:Agent` and reports through the `a2a:TaskUpdater`.
- Two services share one `http:Listener` on :9090: resource functions on an `a2a:RestListener` (`/rest`) and remote functions on an `a2a:JsonRpcListener` (`/rpc`). The card lists both interfaces.
- Each service defines six operations. Streaming is on because both streaming operations exist, push notifications are off
  because none of the push operations do: the card follows the service.
- Open `http://localhost:9090/.well-known/agent-card.json` to show the card the listener served.

**ops-chat** (`tools.bal`, `agent.bal`, `service.bal`, `modules/a2atoolkit/`), the A2A client, backed by an agent on port 8090
- `tools.bal`: the one `a2a:RestClient` for the desk and five `@ai:AgentTool` functions over it: `askOperationsDesk` (`sendMessage`, with
  `inBackground` for `returnImmediately`), `streamFromOperationsDesk`, `getDeskTask`, `listDeskTasks` and `cancelDeskTask`.
- `agent.bal`: the chat agent (Claude Haiku 4.5) with those tools. `service.bal`: the `ai:Listener` chat service at `POST /chat`,
  which the WSO2 Integrator chat panel talks to.
- `modules/a2atoolkit/toolkit.bal`: the complete A2A toolkit for `ballerina/ai` (`A2aToolKit`, an `ai:BaseToolKit`), kept here to show.
  The demo does not use it. To switch, import `ops_chat.a2atoolkit`, create `a2atoolkit:A2aToolKit operationsDesk = check new (deskUrl)`
  and pass `tools = [operationsDesk]`.
- The client is created when `ops-chat` starts, so start the desk first.

## Chat prompts

Send them to `POST http://localhost:8090/chat` (or the chat panel in WSO2 Integrator) with the same `sessionId`, in this order:

1. "What can the operations desk do, and does it support streaming?" (discovers the agent card)
2. "Can you get Nimal access to the staging cloud project?" (the desk pauses: `TASK_STATE_INPUT_REQUIRED`)
3. "It is for the load test of the payments release" (same task, completes with an artifact after about six seconds)
4. "Watch the desk summarise what happened to the gateway overnight." (streamed updates)
5. "Give Kasun access to the vpn, the reason is that he joins the on-call rotation on Monday. Run it in the background."
6. "Is that request still running?" then "Cancel it." then "List the tasks the desk knows about." (`getTask`, `cancelTask`, `listTasks`)

```
curl -s -X POST localhost:8090/chat -H 'Content-Type: application/json' \
  -d '{"sessionId": "demo", "message": "What can the operations desk do, and does it support streaming?"}'
```

Others: "Claim 340 USD for conference travel for Kasun" (asks for the receipt), "Onboarding checklist for Dilini joining the
Identity team on Monday".

## Not covered

Push notifications (they need a webhook receiver), JSON-RPC, and authentication on the listener.
