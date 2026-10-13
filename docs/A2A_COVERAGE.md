# A2A Capability Coverage

What this multi-agent use-case actually tests and demonstrates of the A2A
protocol and the `ballerina/a2a` client, and — just as deliberately —
what it doesn't, and why. Not a pros/cons list: everything here is a real
capability of the spec or the client, marked against real evidence for
whether this specific system exercises it. "Not demoed" is not a defect
in every row below; several are genuine, permanent scope boundaries for a
five-agent internal-tools demo, spelled out as such rather than left
implicit.

Companion to [`DEMO_SCRIPT.md`](DEMO_SCRIPT.md), which is the presenter's
script for everything in the first section below. This document is the
fuller picture, including the parts that don't make it into a live demo.

## BI chat vs. terminal — per A2A method

The main demonstration goes through WSO2 Integrator: BI's chat window
against the orchestrator, not a terminal. BI chat can only show what the
orchestrator's own LLM tool-calling layer actually calls into — every
method below is a real `remote function` on the `a2a-ballerina` client
(`ballerina/client.bal:669-815`); the "Via BI chat?" column says whether
`orchestrator/agent_tools.bal` actually wires it into a tool the chat
agent can invoke, confirmed by grepping that file directly, plus a short
reason either way.

| Method | Via BI chat? | Why |
|---|---|---|
| `sendMessage` | **Yes** | Wired into `delegateToAgent`/`sendToAgent` in `agent_tools.bal` — every chat request that reaches an agent goes through this. `DEMO_SCRIPT.md` Acts 1–2 |
| `getTask` | **Yes** | `sendToAgent` polls it internally after every `sendMessage`, and `getAgentTaskStatus` exposes it directly as a tool. `DEMO_SCRIPT.md` Act 2 |
| `cancelTask` | **Yes** | Wired as the `cancelAgentTask` tool — ask to cancel a task you just started. `DEMO_SCRIPT.md` Act 3 |
| `listTasks` | **Yes** | Wired as the `listAgentTasks` tool — ask about "all my tasks". `DEMO_SCRIPT.md` Act 4, `demo/concurrent_tasks/main.bal` for the fuller scripted proof |
| `sendStreamingMessage` | **No** | `ballerina/ai` (what the chat agent runs on) doesn't support streaming yet — a real framework limitation, not a missing tool. Terminal instead: `verification/phase9_smoke_test` |
| `subscribeToTask` | **No** | Same root cause — nothing in `agent_tools.bal` calls it, and even if it did, `ballerina/ai` has nowhere to stream the result to. Also the mechanism behind connection-drop recovery, which needs direct control over the stream object a chat message can't reach. Terminal instead: `verification/digiops` |
| `createTaskPushNotificationConfig` | **No** | Needs a persistent webhook URL supplied out-of-band; BI chat is one stateless HTTP request per turn with no field for that. Terminal instead: `verification/webhook_receiver` |
| `getTaskPushNotificationConfig` | **No** | Not wired — no tool calls it, and there's no config to read back since nothing in chat ever creates one. Terminal instead: `verification/webhook_receiver` |
| `listTaskPushNotificationConfigs` | **No** | Same reason as above |
| `deleteTaskPushNotificationConfig` | **No** | Same reason as above |
| `getExtendedAgentCard` | **Yes** | Wired as the `getAgentExtendedCard` tool, scoped narrowly (its doc comment tells the model to call it only on an explicit extended/admin-card request). The two agents that gate it (Payroll, PeopleOperations) have their real demo credential held server-side by the orchestrator — the orchestrator plays the authenticated caller, not the chat user — so the tool fetches unauthenticated and authenticated in one call and reports the skill-count difference. `DEMO_SCRIPT.md` Act 5 |

**Summary**: 5 of the 11 real methods (`sendMessage`, `getTask`,
`cancelTask`, `listTasks`, `getExtendedAgentCard`) are wired into the
chat agent's tools and are genuinely BI-chat-demoable today. The other 6
are just as real — every one has a passing terminal script — they're
just not reachable from that specific interface: 2 (`sendStreamingMessage`,
`subscribeToTask`) for a framework reason (`ballerina/ai` doesn't support
streaming yet), 4 (the push-notification-config methods) because nothing
in `orchestrator/agent_tools.bal` wires them to a tool yet — a real gap
to close, not a permanent one, unlike streaming.

## Fully covered — tested and demoed live

| Capability | Evidence |
|---|---|
| All 11 A2A operations (`sendMessage`, `sendStreamingMessage`, `getTask`, `cancelTask`, `subscribeToTask`, `listTasks`, 4× push-notification-config CRUD, `getExtendedAgentCard`) | `DEMO_SCRIPT.md`'s coverage table, Acts 1–5 |
| All 3 transport bindings (REST, JSON-RPC, gRPC) | Same — Parking/TravelExpense (REST), DigiOps/PeopleOperations (JSON-RPC), Payroll (gRPC), confirmed live from each real agent card |
| `TaskState`: `SUBMITTED`, `WORKING`, `COMPLETED`, `CANCELED`, `INPUT_REQUIRED` | `DEMO_SCRIPT.md` Acts 2–3; every agent's staged flow genuinely passes through these |
| Real long-running task lifecycle (staged work, honest in-progress status, real completion) | `DEMO_SCRIPT.md` Act 2, one example per agent |
| Mid-flight cancel (real `cancel()` handler stops staged work) | `DEMO_SCRIPT.md` Act 3 |
| Concurrent, independently-tracked tasks | `DEMO_SCRIPT.md` Act 4, `demo/concurrent_tasks/main.bal` |
| Streaming (`sendStreamingMessage`) | `DEMO_SCRIPT.md` Act 5, `verification/phase9_smoke_test` |
| Push-notification config CRUD + real delivery to a real webhook | `DEMO_SCRIPT.md` Act 5, `verification/webhook_receiver` |
| Extended-card auth gating (2 real mechanisms: gRPC interceptor, bearer token) | `DEMO_SCRIPT.md` Act 5, `verification/payroll`, `verification/peopleoperations` |
| Connection-drop recovery — real deliberate disconnect + `subscribeToTask` resume, live | `DEMO_SCRIPT.md` Act 6, `verification/digiops` |
| Automatic reconnect-with-budget mechanism | `DEMO_SCRIPT.md` Act 6, 9 real tests in `a2a-ballerina` |
| Chaos/error handling (malformed requests, 20x concurrent load, resource-leak sanity) | `DEMO_SCRIPT.md` Act 7, `verification/chaos_test` |
| A real spec-vs-server interop bug, found and fixed | `DEMO_SCRIPT.md` Act 6, `docs/research/a2a-client-and-demo-round-check.md` |

## Real capability, reachable in this demo, but not featured in the live script

These aren't gaps — the code path is real and live-triggerable today —
they're just not part of the happy-path narrative `DEMO_SCRIPT.md` walks
through.

| Capability | Real evidence it's reachable | Why not in the script |
|---|---|---|
| `TaskState.FAILED` | `agents/digiops/agent_executor.py:187,215`, `agents/parking/agent_executor.py:66`, `TravelExpenseAgentExecutorProducer.java:99,158`, `PayrollAgentExecutorProducer.java:99,150` — every agent has a real path to it (LLM produces no usable response, or a tool call genuinely errors) | Needs a real failure to trigger on demand; not something to force artificially just to check a box in a live presentation |
| `TaskState.REJECTED` | `agents/parking/agent_executor.py:107` — fires for real when `is_free(spot, date)` is false (a genuine double-booking) | Trivially demoable (reserve the same spot twice) but not currently in the script — worth adding if a presenter wants one more real state transition |
| JWS/JCS AgentCard signature verification | `a2a-ballerina/ballerina/signature.bal` — real RS256/ES256 verification against RFC 8785 JCS canonicalization, tested against real `a2a.js`-produced signatures (`README.md:108-111`) | None of the 5 demo agents' cards carry a real signature — this is an `a2a-ballerina`-library-level feature, exercised only in that repo's own test suite, never wired into this demo |

## Real client/spec capability, zero real usage anywhere in this demo

Genuine, deliberate scope boundaries — these are things a five-agent
internal-tools demo has no real reason to need, not things that were
attempted and fell short.

| Capability | What's real | Why zero usage here |
|---|---|---|
| Formal `securitySchemes` (AgentCard's 5-member auth-scheme union: apiKey, http, oauth2, openIdConnect, mutualTLS) | The client fully parses all 5 scheme types over both REST/JSON and gRPC wire form (`types.bal:706-910`, `grpc_binding.bal:616-683`) | None of the 5 agents declare one — Payroll's gRPC interceptor and PeopleOperations' bearer-token gate are both real, but purely application-level, never advertised via the card's formal auth-scheme field. This demo proves manual, out-of-band auth works; it doesn't prove the discover-a-scheme-and-authenticate-automatically flow, because nothing here implements the server side of that flow either |
| mTLS | `MutualTlsSecurityScheme` is fully typed; the client has no higher-level helper beyond what `http:ClientConfiguration.secureSocket` already provides generically | Documented, permanent, tracked limitation — not silently missing. See `a2a-ballerina/README.md:180-185` and issue #13 |
| `Part` types beyond text (`file`, `data`) | The client's `Part` union and all 3 transport bindings support them structurally | All 26 real `Part` constructions across all 5 agents are `TextPart`/`new_text_part` — every message in this whole system is plain text. No business scenario here (parking, IT tickets, HR, payroll, expenses) genuinely needs a file attachment or structured-data part today |
| Multi-tenancy (`tenant` param) | Every client class (`RestClient`/`JsonRpcClient`/`GrpcClient`) accepts a real `tenant` param and path-prefixes REST requests with it | This demo is a single WSO2-internal deployment — zero real multi-tenant requirement, zero usage anywhere in `orchestrator/`, `demo/`, or `verification/` |
| Extensions (`A2A-Extensions` header / `requestedExtensions`) | Real on all 3 transports (`jsonrpc_client.bal:136-137`, `grpc_client.bal:152-153`, `rest_client.bal:264-265`) | No real extension URI is defined for any of the 5 agents to declare or request — tested only against `a2a-ballerina`'s own mock server, never demoed live |
| A2A v0.3 backward compatibility (`compat_v03.bal`) | Real, client-tested translation layer | All 5 real agents are confirmed v1.0-only (Python `a2a-sdk` 1.2.1, Java `a2a.sdk.v1.version` 1.4.0.Final) — no v0.3 server exists anywhere in this demo to exercise it against |
| `getTask`'s `historyLength` param | Real, typed parameter on every client | `orchestrator/agent_tools.bal`'s two `getTask` call sites both omit it — every real call in this demo uses the default |
| Task/message `metadata` field | Real, typed `map<json>` field throughout | No agent or orchestrator code path in this demo ever sets or reads a real value into it — every call site passes `null` or omits it |

## Genuine capability gap

| Capability | Status |
|---|---|
| `TaskState.AUTH_REQUIRED` | Zero real usage anywhere. `requiresAuth()` exists as a real method on the Java SDK's `AgentEmitter` (confirmed via `javap` decompilation earlier this session), but no business logic in any of the 5 agents ever calls it. Unlike the other rows above, this isn't a "no real reason to need it" scope boundary — an agent that itself required step-up authentication mid-task is a real, plausible scenario this demo's business domains just never happened to need. Worth building if a future scenario calls for it |

## Not a real capability at all — checked, not assumed

**Task queuing.** The A2A v1.0.0 spec's `TaskState` enum has no `QUEUED`
value, and no agent in this demo implements admission control. What's
real and demoed instead: multiple genuinely concurrent, independently
tracked tasks by task id (`DEMO_SCRIPT.md` Act 4) — checked directly
against the spec and the codebase before deciding this, not assumed
because "queuing" sounded like something a task-based protocol should
have.
