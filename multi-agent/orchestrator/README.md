# Orchestrator

WSO2 Employee Concierge orchestrator: a real `ballerina/ai` `Agent` on a
real Anthropic model, routing employee requests to five real downstream
agents via five real `ballerina/a2a` tool functions, plus the
push-notification webhook receiver (Phase 6) all five agents can point
at — one process hosting both the outbound agent-calling logic and this
inbound receiver.

Real Anthropic backing via `ballerinax/ai.anthropic` from the start — no
stub model. See the
["Everything real, nothing simulated"](../CLAUDE.md) rule for why.

## Stack

Ballerina · `ballerina/http` (webhook receiver, port **9090**) ·
`ballerina/ai` + `ballerinax/ai.anthropic` (routing agent) ·
`ballerina/a2a` (five real client connections to Parking, DigiOps,
PeopleOperations, Payroll, and Travel & Expense) · `ai:Listener` (chat
service, port **8090** — see "Chatting with it" below).

**Must always be built/run with `--sticky`** — see the real
grpc/http-native ABI-coupling issue noted in `.gitignore` and in the
Phase 7 scaffolding commit; `Dependencies.toml` is committed for this
package specifically because of it.

## Run it

No downstream agent needs to be up for the orchestrator itself to boot —
`agent_tools.bal` resolves a real `a2a:Client` for an agent only when
something actually delegates to it, not eagerly at module init (this
used to not be true; see the "Discover-and-delegate" note below).
Verified directly: booted the orchestrator with zero downstream agents
running and it still answered chat requests, failing gracefully only on
the specific agent it couldn't reach.

```sh
export ANTHROPIC_API_KEY=...    # required for real routing / real answers
bal run --sticky
```

For a real demo you obviously still want the five agents actually up —
`../scripts/start-agents.sh` brings up all five (then stops, leaving the
orchestrator for you to run/debug separately, including from WSO2
Integrator: BI's Run/Debug button or chat panel).

Without `ANTHROPIC_API_KEY`, the orchestrator still boots, but any real
routing request fails gracefully with a typed error — verified, see
below.

## What it does

- **`concierge` (`ai:Agent`)** — the real routing layer. Given a natural-language
  employee request, the real Anthropic model discovers the real downstream
  agents, picks the right one, and relays its real answer back. Full
  routing verification (does it pick the right agent) is Phase 9's job,
  once a real key is supplied.
- **`POST /concierge/chat` (`chat_service.bal`)** — `concierge` exposed on
  an `ai:Listener` (port 8090) as a real `ai:ChatService`, so it can be
  chatted with directly (`{"sessionId": "...", "message": "..."}` in,
  `{"message": "..."}` out) and, per below, driven from WSO2 Integrator:
  BI's chat panel.
- **Discover-and-delegate (`agent_tools.bal`)** — five generic tools, not
  one named tool per agent per operation: `discoverAgents` resolves every
  known agent's real `AgentCard` (name, description, skills) on demand,
  so `concierge` reads real capabilities instead of hand-written
  per-agent docstrings; `delegateToAgent(agentName, message)` sends a new
  request to whichever agent the model picked;
  `cancelAgentTask`/`getAgentTaskStatus`/`listAgentTasks(agentName, ...)`
  act on an existing task by id, or list everything an agent's seen.
  Mirrors the real pattern WSO2 Integrator: BI itself generates (see
  `~/WSO2Integrator/wso2-integrator-a2a/a2ademoassistant/functions.bal`)
  rather than the twenty named functions this replaced. A real
  `a2a:Client` per agent is created and cached lazily, on first actual
  use — not eagerly for all five at module init the way it used to be,
  so **no downstream agent needs to be up for the orchestrator itself to
  boot** (verified: booted with zero agents running, chat still answered,
  failing gracefully only on the specific agent asked about). `delegateToAgent`
  replies include the real task id (e.g. "(task id: abc-123)") when the
  result is a `Task`, so `concierge`'s own conversation memory lets it
  call the matching cancel/status tool on a later turn. Push-notification
  config CRUD is deliberately not exposed as a chat tool — it doesn't map
  to a synchronous request/reply turn, and support for it is asymmetric
  across the five agents anyway. All five tools are directly callable and
  independently testable without the AI layer at all.
- **Real long-running tasks (PeopleOperations onboarding, DigiOps hardware
  provisioning)** — both now genuinely take ~10 real minutes, staged and
  cancellable, instead of finishing instantly. `sendToAgent` passes
  `returnImmediately: true` on every `sendMessage` call (every agent that
  creates a real `Task` — all of them except Parking's plain availability
  check — otherwise blocks on the underlying `http:Client`'s stock 30s
  timeout regardless of the real work's actual duration), then polls
  `getTask` for up to 20s before falling back to the honest "still
  working, task id: X" reply `summarizeTask` already produces. This is why
  even fast agents now take one extra quick round trip instead of a single
  blocking call — content is unaffected either way.
  Payroll's payslip-correction review and Travel & Expense's
  client-entertainment claim review are the same real staged pattern
  (`PAYROLL_REVIEW_STEP_DELAY_SECONDS`, `TRAVELEXPENSE_REVIEW_STEP_DELAY_SECONDS`),
  Java rather than Python — an ordinary (non-entertainment) expense claim
  skips the staged wait entirely and resolves fast, same catalog-vs-approval
  split as DigiOps' hardware provisioning.
  Each agent's own step-delay env var
  (`ONBOARDING_STEP_DELAY_SECONDS`, `OFFBOARDING_STEP_DELAY_SECONDS`,
  `HARDWARE_PROVISIONING_STEP_DELAY_SECONDS`, `PAYROLL_REVIEW_STEP_DELAY_SECONDS`,
  `TRAVELEXPENSE_REVIEW_STEP_DELAY_SECONDS`
  — all default ~200s × steps) is read once at that agent process's
  start. **Setting it in the shell you happen to run `bal test`
  or `curl` from does nothing** — it only takes effect if set in `.env`
  *before* `scripts/start-agents.sh`/`start-all.sh` launches those
  processes. Restart the agents to switch between the real ~10-minute
  pace and a shorter one for manual testing.
- **Employee identity** — write actions (reservations, tickets, corrections,
  claims) are tied to a real employee name: `concierge`'s system prompt
  asks for it if missing and reuses it for the rest of the conversation;
  Parking and DigiOps have real `reserved_by`/`raised_by` fields backing
  it (Payroll and Travel & Expense already had `employeeName` fields from
  the start). "Who reserved/raised/filed X" is a real, answerable
  question.
- **`maxIter = 10`** — `ai:Agent`'s own default scales with tool count
  (`max(tools.length(), 10)`); a real, confirmed-non-deterministic
  tendency of this model+framework combo to occasionally re-call a tool
  several times for one question is documented in GitHub issue #24 —
  dropping from twenty named tools to five generic ones (this file)
  measurably reduced it in re-testing (see the issue's own follow-up
  comment), though it isn't fully eliminated, so an explicit cap stays in
  place rather than relying on the auto-scaled default.

- **`POST /webhooks/push`** — accepts a real push-notification delivery
  from any agent's `PushNotificationSender`. Handles both wire shapes
  seen in this demo: a2a-java's flat `{"id": ..., "status": {...}}`, and
  a2a-python's `StreamResponse`-enveloped `{"task": {...}}` /
  `{"statusUpdate": {...}}`. Logs each real delivery (task ID,
  `status.state`, `X-A2A-Notification-Token`) into an in-memory list.
- **`GET /webhooks/received`** — returns everything received so far, as
  JSON. Real introspection, not a mock — used by
  `verification/webhook_receiver` to assert delivery actually happened.

## Chatting with it

Once running (locally or via BI's Run/Debug), talk to `concierge` directly
over HTTP:

```sh
curl -s http://127.0.0.1:8090/concierge/chat \
  -H 'Content-Type: application/json' \
  -d '{"sessionId": "demo-1", "message": "is there parking available today?"}'
```

**In WSO2 Integrator: BI**: run `../scripts/start-agents.sh` first (see
"Run it" above — BI's Run button doesn't start the five downstream
agents for you), then open `orchestrator/` in BI, select the Design
canvas's `AI Agent Service` entry point (`chatListener` → `/concierge`),
and use its chat panel — BI drives the same `POST /concierge/chat`
resource under the hood. See
[`../docs/research/wso2-integrator-bi-compatibility.md`](../docs/research/wso2-integrator-bi-compatibility.md)
for why this file (`chat_service.bal`) had to be added for BI to render
`concierge` as a chat agent at all, rather than showing only the webhook
receiver's plain `http:Listener`.

## A real finding from building this

Push-notification delivery was verified against all three agents that
declare the capability (Parking, Payroll, Travel & Expense), but Payroll
and Travel & Expense's delivery is **genuinely racy** in a2a-java
1.1.0.Final, not flaky test infrastructure: the SDK registers an inline
`taskPushNotificationConfig` (sent in the same `sendMessage` call) only
after consuming the first event back from the executor
(`DefaultRequestHandler.onMessageSend`), so a synchronous agent whose
entire submit → startWork → LLM-call-fails sequence happens within the
same instant can race past that registration before it lands. The
terminal `FAILED` transition specifically never delivers at all: an
uncaught executor exception is converted to `FAILED` by a framework
handler that doesn't route through the same
`AgentEmitter -> MainEventBusProcessor -> PushNotificationSender`
pipeline an explicit status update does. Parking (Python, `a2a-sdk`) has
no equivalent race and delivers reliably across its whole lifecycle,
including the terminal state.

`verification/webhook_receiver` documents this in full and handles it
honestly — Parking is asserted deterministically in one attempt; Payroll
and Travel & Expense retry a fresh request (a legitimate technique for an
asynchronous, eventually-racy real system) until one delivery lands,
rather than asserting something the SDK doesn't actually guarantee.

## Verification: push-notification delivery (Phase 6)

[`../verification/webhook_receiver`](../verification/webhook_receiver) is
a real `ballerina/a2a` script exercising all three agents against a real
running receiver — no key needed for any of it, since every check here is
about the push-notification mechanism itself, not LLM content:

```sh
# start the receiver, then Parking, Payroll, and Travel & Expense (see
# each agent's own README), then:
cd verification/webhook_receiver
bal run --sticky
```

## Verification: tools and the routing agent (Phase 7)

No separate `verification/orchestrator` package — the tools and the agent
are internal logic, not a new server-side protocol surface the way every
other agent's `AgentExecutor` was, so `bal test` (Ballerina's own,
real testing framework — not a mock) is the right tool for this, the same
way it would be for any other internal Ballerina package logic:

```sh
# start all five downstream agents first (see each one's own README), then:
cd orchestrator
bal test --sticky
```

`tests/agent_tools_test.bal` calls `delegateToAgent` against each of
the five real agents directly, plus `discoverAgents` and the
cancel/status/list tools — all five downstream agents are real
LLM-backed agents, so each `delegateToAgent` call is asserted for real
content with a key present, and graceful failure without one.
`tests/concierge_agent_test.bal` does the same for the real `ai:Agent`
itself. Every check here runs against real, live agent processes over the
real `ballerina/a2a` wire — nothing here is mocked, only the *invocation
mechanism* (a test runner instead of a standalone script) differs from
the other verification/ packages.
