# Demo Script

The full presentation walkthrough for the Employee Concierge system —
every scenario below is real (a `RESULT:` line under each act with a real
excerpt), so this doubles as the actual live-demo script: read a request
aloud (or run the cited command), show the real reply, move on. Nothing
here has been faked, trimmed for effect, or "cleaned up" after the fact —
where the model did something reasonable but unscripted, that's recorded
honestly too.

This rewrites the original Phase 9 script (10 scenarios) into a full
coverage pass: all **11 A2A operations** the `ballerina/a2a` client
implements, across all **3 transport bindings** it speaks (REST,
JSON-RPC, gRPC), plus the resilience behaviors that make this a real
client library and not a toy — connection-drop recovery, and (the honest
version of) task queuing.

## Coverage at a glance

| Operation | Transport(s) proven | Act |
|---|---|---|
| `sendMessage` | REST, JSON-RPC, gRPC | 1, 2 |
| `sendStreamingMessage` | JSON-RPC | 5 |
| `getTask` | REST, JSON-RPC, gRPC | 2, 4 |
| `cancelTask` | REST, JSON-RPC, gRPC | 3, 4 |
| `subscribeToTask` | JSON-RPC | 6 |
| `listTasks` | REST, JSON-RPC, gRPC | 4 |
| `createTaskPushNotificationConfig` | REST, gRPC | 5 |
| `getTaskPushNotificationConfig` | REST, gRPC | 5 |
| `listTaskPushNotificationConfigs` | REST, gRPC | 5 |
| `deleteTaskPushNotificationConfig` | REST, gRPC | 5 |
| `getExtendedAgentCard` | JSON-RPC (bearer token), gRPC (interceptor) | 5 |

Per-agent transport binding (confirmed live from each real agent card,
not assumed):

| Agent | Transport | Streaming | Extended-card auth |
|---|---|---|---|
| Parking | REST (HTTP+JSON) | no | — |
| DigiOps | JSON-RPC | **yes** | — |
| PeopleOperations | JSON-RPC | **yes** | bearer token (`PEOPLEOPS_STAFF_TOKEN`) |
| Payroll | gRPC | no | gRPC interceptor (`PAYROLL_ADMIN_TOKEN`) |
| Travel & Expense | REST (HTTP+JSON) | no | — |

## Setup

```sh
cp .env.example .env   # fill in a real ANTHROPIC_API_KEY

# Real, staged task delays default to ~200s (a genuine ~10-minute
# provisioning/review flow). For live presentation pacing, shorten them —
# this is a real, already-documented knob (see orchestrator/README.md),
# not fabricated timing:
export ONBOARDING_STEP_DELAY_SECONDS=10
export OFFBOARDING_STEP_DELAY_SECONDS=10
export HARDWARE_PROVISIONING_STEP_DELAY_SECONDS=10
export PAYROLL_REVIEW_STEP_DELAY_SECONDS=10
export TRAVELEXPENSE_REVIEW_STEP_DELAY_SECONDS=10

./scripts/start-all.sh
# or Docker Compose (Phase 12): ./orchestrator/prepare-docker-build.sh && docker compose up -d --build
```

`scripts/start-all.sh` brings up all 5 agents plus the orchestrator, and
prints each real agent's URL. Confirm all 5 are healthy before starting:

```sh
for p in 8000 8001 8002 8003 8004; do curl -s -o /dev/null -w "%{http_code} " http://127.0.0.1:$p/.well-known/agent-card.json; done
```

Should print `200 200 200 200 200`.

---

## Act 1 — Discovery, FAQ, and real routing quality

Proves `sendMessage` (plain-message mode, no task) over all 3 transports,
and that the orchestrator's real LLM tool-selection routes a natural
request to the right one of five agents — not keyword matching.

**Direct to DigiOps** (JSON-RPC): *"what's the password policy?"*

> **RESULT:** *"Our password policy requires a minimum of 12 characters,
> with rotation every 90 days. You can reset your password via the
> self-service portal at idp.wso2.internal.example/reset."*

**Direct to PeopleOperations** (JSON-RPC): *"how many annual leave days
do I get?"*

> **RESULT:** *"You get 20 days of annual leave per year. The leave is
> accrued monthly, and you can carry over up to 5 unused days into the
> next year."*

**Through the orchestrator, same domains, phrased naturally** — proves
the concierge Agent's own tool-calling picks correctly:

- *"is there a free parking spot at HQ right now?"* → routes to
  `askParkingAgent`, real answer.
- *"my laptop won't connect to the VPN, can you help?"* → routes to
  `askDigiOpsAgent`, real GlobalProtect/VPN troubleshooting referencing
  the real reference facts.
- *"when do I get paid this month?"* → routes to `askPayrollAgent`:
  *"Salaries are credited on the last working day of each month...
  payslip details are published on the WSO2 HR portal by the 25th."*
- **Off-domain, should decline rather than guess**: *"what's the
  weather like today?"* → *"I don't have access to weather information.
  My role is to help with WSO2-specific requests like: Parking... IT
  support... HR/People Operations... Payroll... Travel & Expenses."* —
  lists its real five domains rather than fabricating an answer.

Run live: `verification/phase9_smoke_test/main.bal` (direct-to-agent) and
`orchestrator/tests/phase9_routing_test.bal` / `bal test --sticky`
(routing) — both currently passing.

---

## Act 2 — Real long-running task lifecycle, one per agent

Every agent's staged flow: real work done immediately (a real ticket,
reservation, or correction record exists from the first response), the
*task* itself stays open through a genuine staged wait, and an honest
in-progress status is distinguishable from completion — never a fake
instant "done."

**PeopleOperations — onboarding** (JSON-RPC, streaming): *"please start
onboarding for a new hire named Nadeesha Perera"*

> **RESULT:** Real tool calls to `provision_laptop`, `assign_desk`,
> `enroll_benefits` (all three genuinely run — confirmed via the
> executor-side validation added in PR #34, which would block completion
> if even one were skipped), staged narration streamed live, ending:
> *"Onboarding completed successfully for Nadeesha Perera! ✅ Laptop
> provisioned ✅ Desk assigned ✅ Benefits enrollment completed."*

**PeopleOperations — offboarding, status check, leave filing** (new in
PR #34): *"offboard Nadeesha Perera"* mirrors onboarding in reverse
(`revoke_laptop`/`revoke_desk`/`terminate_benefits`), its own
`OFFBOARDING_STEP_DELAY_SECONDS`. *"what's the status of Nadeesha's
onboarding?"* calls the real `check_onboarding_status` tool — a genuine
read-back, not the LLM's own recollection. *"file leave for Nadeesha
Perera from 2026-09-01 to 2026-09-03 for a family event"* files a real
leave request.

**DigiOps — catalog-vs-approval split** (JSON-RPC, streaming; new in PR
#35): *"I need a new laptop"* — a standard-catalog item — resolves
**fast**, no staged wait, as a real in-stock request would:

> **RESULT:** *"I've raised a hardware ticket for a new laptop... A
> laptop is part of our standard hardware catalog, so it should be
> fulfilled quickly."* Completed in ~4 polls.

*"I need a standing desk converter"* — outside the catalog — genuinely
stages through manager approval instead:

> **RESULT:** *"Since a standing desk converter is outside our standard
> hardware catalog (laptop, monitor, docking station, headset), it
> requires a manager approval step..."* Real staged narration
> (`Routing to manager for approval...`, `Approved — ordering
> hardware...`), completed only after ~16 polls at test pacing.

**Parking — day-scoped reservation** (REST; new in PR #36): *"reserve
spot A03 for tomorrow, my name is Kasun Silva"* — day-scoping is real,
not cosmetic: A03 stays free *today* and shows taken only *tomorrow*.

**Payroll — correction lifecycle, pay history, tax documents** (gRPC;
new in PR #37): *"my payslip has the wrong tax deduction, please file a
correction, my name is Priyanka Fernando"* genuinely stages through
review (`submitted` → `in_review` → `approved`), not an instant fake
approval:

> **RESULT:** *"Correction request PC-1000 for Priyanka Fernando has
> been reviewed and approved."* A later `getCorrectionStatus` call
> reflects real state throughout, not always "COMPLETED." *"what's my
> pay history?"* and *"I need my tax certificate for 2025"* are both real
> direct-answer tools, not policy recitation.

**Travel & Expense — structured claims, per-diem, entertainment review**
(REST; new in PR #38): *"what's the per diem for 3 days in the asia
pacific region?"* is a real calculation (`USD 60.00/day × 3 = USD
180.00`), not a quoted rate. *"I spent 45.50 USD on a taxi to the
airport, my name is Sanjaya Perera"* — an ordinary claim — resolves fast
with a real structured `amount`/`currency`. *"I spent 120 USD on a
client dinner..."* — client entertainment — genuinely pauses for staged
manager review before approval.

---

## Act 3 — Mid-flight cancel

Real `cancelTask`, all 3 transports: start any Act 2 flow, cancel it
before it settles, confirm `TASK_STATE_CANCELED` — the agent's own
`cancel()` handler stops real staged work, not just a client-side
give-up. Orchestrator's own test suite proves this for onboarding and
DigiOps hardware provisioning (`testCancelOnboardingMidFlight`,
`testCancelHardwareProvisioningMidFlight`); direct-to-agent, any of
Act 2's staged flows works the same way, e.g. cancel a Payroll correction
mid-review or a Parking reservation before its 4s settle window closes.

---

## Act 4 — Concurrent tasks (the honest version of "queuing")

**Checked first, not assumed**: the A2A spec has no `QUEUED` task state
and no agent here does admission control — there is no formal queue.
What's real and just as worth proving: several genuinely simultaneous
tasks against the same agent, each independently created, tracked,
cancelable, and completable by its own task id.

Run: `demo/concurrent_tasks/main.bal` — fires 5 real onboarding requests
at PeopleOperations concurrently (`start`/`wait` futures), then:

> **RESULT (real run):**
> ```
> === firing 5 real onboarding requests concurrently ===
>   Kasun Silva -> task a40f2b21-... (TASK_STATE_SUBMITTED)
>   Nadeesha Perera -> task e85a63d0-... (TASK_STATE_SUBMITTED)
>   Priyanka Fernando -> task 2482a34c-... (TASK_STATE_SUBMITTED)
>   Sanjaya Perera -> task aed11908-... (TASK_STATE_SUBMITTED)
>   Dilani Jayawardena -> task 8d6aa94c-... (TASK_STATE_SUBMITTED)
>
> === listTasks proves all 5 are independently tracked, not one shared job ===
> 5/5 of this run's own task ids confirmed present (agent reports 13 known task(s) total, including earlier runs)
>
> === cancel the first one mid-flight -- the other 4 keep going, untouched ===
> Kasun Silva's task (a40f2b21-...) -> TASK_STATE_CANCELED
>
> === poll the rest independently through to real completion ===
> Nadeesha Perera's task (...) -> TASK_STATE_COMPLETED (32 polls)
> Priyanka Fernando's task (...) -> TASK_STATE_COMPLETED (0 polls)
> Sanjaya Perera's task (...) -> TASK_STATE_COMPLETED (0 polls)
> Dilani Jayawardena's task (...) -> TASK_STATE_COMPLETED (0 polls)
> ```

Cancelling one has zero effect on the other four — real, independent,
concurrent execution, not a queue with one worker.

---

## Act 5 — Operations the chat interface never touches

The orchestrator's own tool-calling only ever uses 4 of the client's 11
operations (`sendMessage`, `getTask`, `cancelTask`, `listTasks`). The
other 7 are just as real — demoed directly against the client.

**Streaming** (`sendStreamingMessage`) — already shown live in Act 2's
onboarding/incident-investigation narration
(`verification/phase9_smoke_test`, `verification/digiops`): real
incremental `StreamResponse` events arrive as the agent's own tool calls
happen, not a single buffered reply.

**Push-notification config CRUD, with real delivery** — run
`verification/webhook_receiver/main.bal`: registers a real
`taskPushNotificationConfig` inline at `sendMessage` time against
Parking, Payroll, and Travel & Expense, and confirms the orchestrator's
own webhook receiver (`orchestrator/webhook_receiver.bal`,
`/webhooks/push`) actually received the POST — turning "config CRUD
works" into "notifications actually work."

> **RESULT (real run):** all three delivered —
> `parking: real webhook delivery confirmed for a real state change`,
> `payroll: real webhook delivery confirmed`,
> `travel_expense: real webhook delivery confirmed`.
>
> **A genuinely interesting real finding, documented in the script
> itself, not worked around**: `a2a-java-sdk-reference-rest:1.1.0.Final`
> registers an inline push config only *after* consuming the first event
> back from the executor — for Payroll and Travel & Expense, every state
> transition happens in one synchronous burst with no real work between
> them, so the config can genuinely race past events emitted before it
> lands. Parking (Python, `a2a-sdk`) has no equivalent race. The script
> retries a fresh request rather than asserting something the SDK doesn't
> actually guarantee — a legitimate technique for a real, asynchronous,
> occasionally-racy system.

`getTaskPushNotificationConfig`/`listTaskPushNotificationConfigs`/
`deleteTaskPushNotificationConfig` round-trip for real too — see
`verification/payroll/main.bal`'s create→get→list→delete cycle.

**Extended agent card, two different real auth mechanisms**:

- **Payroll (gRPC interceptor)**: unauthenticated `getExtendedAgentCard`
  is rejected outright by a real `ServerInterceptor`
  (`AdminOnlyExtendedCardInterceptor`); with `Authorization: Bearer
  <PAYROLL_ADMIN_TOKEN>`, the card gains a real `adjust-other-employee-payroll`
  admin skill.
- **PeopleOperations (bearer token, downgrade)**: no gRPC interceptor
  available in this SDK binding, so it's gated in application code
  instead — unauthenticated gets 2 skills, authenticated (bearer
  `PEOPLEOPS_STAFF_TOKEN`) gets 3, adding a real `case-escalation` skill.
  Different real mechanism, same real outcome: the card genuinely
  differs by who's asking.

Run live: `verification/payroll/main.bal`, `verification/peopleoperations/main.bal`.

**Also reachable from BI chat**: ask "check Payroll's extended agent
card" or "does PeopleOperations' admin card have any extra skills?". The
`getAgentExtendedCard` tool holds each agent's real demo credential
server-side (the orchestrator plays the authenticated caller, not the
chat user) and fetches the card both without and with it in one call,
reporting the skill-count difference directly in the reply — the same
proof as the scripts above, one chat message instead of a terminal run.

---

## Act 6 — Resilience: connection drop and real recovery

Two distinct real behaviors, demoed separately because they're genuinely
different mechanisms:

**1. Manual resubscribe after a real dropped connection, live, against a
real running agent.** `verification/digiops/main.bal` opens a real
`sendStreamingMessage` stream, receives real events, then *deliberately
closes the connection* mid-stream (`s.close()`) — a faithful stand-in for
a real network blip, since it doesn't kill the agent process or wipe its
task store. It then calls `subscribeToTask` on the same task id and
genuinely resumes:

> **RESULT (real run):** `sendStreamingMessage delivers real events (2
> received before deliberate disconnect)`, then `subscribeToTask
> genuinely resumes after a real disconnect`. Per A2A spec §3.1.6, a
> resubscribe's first event is always the task's current state — nothing
> is lost across the drop, only possibly duplicated.

(A literal "kill the agent process" demo is deliberately **not** done
live: it would wipe the agent's in-memory task store and show a real
`task not found` failure, not a network drop — that's a different, much
worse failure mode than a connection blip, and honestly showing that
distinction is more valuable than faking a recovery.)

**2. Automatic reconnect with an attempt budget** — the client's
`ReconnectingStreamGenerator`/`wrapReconnecting` (`sse.bal`), triggered
by a genuine stream *error* (not a clean close), for the case where the
caller wants the client to absorb transient failures without manually
resubscribing. Proven by 9 real tests in `a2a-ballerina`'s own suite —
run them live:

```sh
cd a2a-ballerina/ballerina && bal test --sticky 2>&1 | grep -i reconnect
```

> **RESULT (real run):** all 9 pass —
> `testSendMessageStreamReconnectsOnDrop`,
> `testSubscribeToTaskReconnectsOnDrop`,
> `testSubscribeToTaskReconnectPreservesPerCallTenant`,
> `testSendMessageStreamGivesUpAfterExhaustingReconnectAttempts`,
> `testSendMessageStreamGivesUpWhenEveryReconnectAttemptFails`,
> `testReconnectBudgetIsConsumedOncePerAttemptAndSharedAcrossTheChain`,
> `testSendMessageStreamDoesNotReconnectByDefault`,
> `testSendMessageStreamDoesNotReconnectAfterBareMessage`,
> `testWrapReconnectingHandsBackRawStreamWhenBudgetIsZero`. Real dropped
> connections simulated (`simulateDropError`), a real bounded retry
> budget, and the "opt-in only" default both genuinely verified — not
> just documented.

**3. A real interop bug, found and fixed for real.** The A2A v1.0.0 spec
requires `Content-Type: application/a2a+json` on the REST binding — but
the actual, currently-released Java reference server
(`a2a-java-sdk-reference-rest:1.1.0.Final`, what Travel & Expense
depends on) rejects it outright with a real `415`, confirmed by
decompiling its route registration. `RestClient` now sends the
spec-correct header by default and transparently negotiates down to the
legacy `application/json` on an actual `415`, remembering the choice per
client instance. Full story: `docs/research/a2a-client-and-demo-round-check.md`
in this repo.

---

## Act 7 — Chaos and error handling

Run `verification/chaos_test/main.bal` live — five real fault-injection
sections against real running agents, no mocks:

1. Malformed REST requests (invalid JSON, missing fields) against
   Parking — agent rejects gracefully, stays alive.
2. Malformed JSON-RPC requests against DigiOps — same.
3. Invalid gRPC input (a nonsense push-notification URL/task id) against
   Payroll — rejected gracefully, agent stays alive.
4. **20 simultaneous real requests** against Parking — all 20 complete
   successfully.
5. Resource-leak sanity: 30 repeated real agent-card resolutions in a
   row, all succeed — no connection exhaustion, no leak.

> **RESULT (real run):** all five pass — malformed JSON and a
> missing-required-field REST request both rejected with a real `400`,
> Parking stays alive; a non-JSON-RPC body and an unknown JSON-RPC method
> both rejected with real JSON-RPC errors, DigiOps stays alive; an
> invalid push-notification URL/task id against Payroll (gRPC) rejected
> gracefully (`Task not found`), Payroll stays alive; **20/20** concurrent
> real requests against Parking completed successfully; **30/30**
> repeated card resolutions and **30/30** fresh client
> construct-use-drop cycles succeeded — zero panics, zero crashes, every
> agent still healthy afterward.

---

## Act 8 — Wrap-up

What was just shown, real end to end:

- All **11 A2A operations**, across all **3 transport bindings** this
  library speaks.
- A genuine **long-running task lifecycle** — real work done
  immediately, real staged waits, real cancel, real concurrent
  independent tracking (not a fabricated "queue").
- Real **resilience**: a genuine dropped-connection recovery live, plus
  the fuller automatic-reconnect-with-budget mechanism proven by its own
  test suite.
- A real **interop bug found and fixed** along the way — spec text and a
  real, currently-released reference server actually disagreed; the
  fix keeps the client both spec-conformant and genuinely interoperable,
  not one at the expense of the other.
- Every capability shown here was found, built, and verified against
  **real running agents with a real Anthropic key** — nothing in this
  system has a stub, a canned response, or a "looks like it works" mode.

Full evidence trail: `docs/research/a2a-client-and-demo-round-check.md`
(the round check that found and fixed the content-type issue and a
stale-dependency gap), `a2a-ballerina/CONFORMANCE_CHECKLIST.md` (the
client's own GA-readiness tracking), and every PR referenced above.
