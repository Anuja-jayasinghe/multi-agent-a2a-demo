# Payroll Agent

A real A2A listener agent for WSO2 Payroll — payslip corrections, payroll
FAQs, and admin-only payroll adjustment via a genuinely gated extended
agent card. Generic name for now — see
[`../../NAMING.md`](../../NAMING.md) for what's still pending.

Real Anthropic backing via langchain4j from the start — no stub model.
See the ["Everything real, nothing simulated"](../../CLAUDE.md) rule for
why.

## Stack

Java 17 · Maven · Quarkus · [`a2a-java`](https://github.com/a2aproject/a2a-java)
SDK 1.4.0.Final (gRPC binding) · `quarkus-langchain4j-anthropic`
(`@RegisterAiService`) · gRPC on port **9003**, plain HTTP (agent-card
discovery only) on port **8003**.

gRPC and HTTP run on **separate ports** — Quarkus's own default, kept
deliberately rather than combined onto one port the way the reference
sample this was modeled on does it. A combined port broke the well-known
agent-card HTTP GET during verification (see the scaffolding commit for
the full story). The HTTP listener is also pinned to HTTP/1.1
(`quarkus.http.http2=false`): ballerina/http's client defaults to HTTP/2
cleartext prior-knowledge negotiation, which doesn't interop with
Vert.x's h2c handling here.

## Run it

```sh
cd agents/payroll
mvn -DskipTests -Dquarkus.analytics.disabled=true package
export ANTHROPIC_API_KEY=...        # required for real payroll answers
export PAYROLL_ADMIN_TOKEN=...      # required to test authenticated extended-card access
java -jar target/quarkus-app/quarkus-run.jar
```

Without `ANTHROPIC_API_KEY`, the agent boots and serves its card
correctly, but every real request fails gracefully with a typed error —
verified, see below. `PAYROLL_ADMIN_TOKEN` is independent of the LLM key
and can be set without it — the extended-card gating below works today
with no key at all.

Agent card: `http://127.0.0.1:8003/.well-known/agent-card.json`
gRPC endpoint: `localhost:9003`

## What it does

- **Payroll FAQs and payslip corrections (`sendMessage`)** — real Claude
  (via langchain4j) answering from fictional-but-WSO2-styled payroll
  reference text (`PayrollAgent.java`'s system prompt): pay cycle,
  payslip publication date, tax deduction basis, correction deadline. When
  the request describes something wrong with a payslip, the model calls a
  real tool (`PayrollTools.fileCorrectionRequest`) that mutates real
  in-memory state and returns a correction ID; a follow-up status check
  calls `getCorrectionStatus`.
- **Task lifecycle (`getTask`/`cancelTask`/`listTasks`)** — every request
  drives a real A2A task through `submit -> startWork -> complete`, or
  fails it genuinely if the underlying LLM call errors.
- **Push-notification config CRUD** — `InMemoryPushNotificationConfigStore`
  is auto-wired by CDI (an `@ApplicationScoped` bean the a2a-java Quarkus
  reference module picks up automatically — no explicit producer needed).
  This is the one agent in the demo proving all four operations
  (`create`/`get`/`list`/`delete`), including `listTaskPushNotificationConfigs`,
  the least-covered op elsewhere. Pure data, no LLM involved, verified
  against a real (if LLM-failed) task.
- **`getExtendedAgentCard`, admin-gated** — an admin-only
  `adjust-other-employee-payroll` skill on the extended card. Gated by a
  real bearer-token check enforced by a Quarkus `@GlobalInterceptor`
  (`AdminOnlyExtendedCardInterceptor`) scoped to only the
  `GetExtendedAgentCard` RPC. **This is a different shape than
  PeopleOperations's gating**: the a2a-java gRPC reference module
(1.4.0.Final) has no per-caller extended-card modifier hook the way the
  Python SDK does — confirmed by reading the SDK's own
  `GrpcHandler`/`QuarkusGrpcHandler` source, where `getExtendedAgentCard()`
  is a fixed, context-free bean lookup. So instead of serving a downgraded
  card to an unauthenticated caller, this agent rejects the RPC outright
  (`PERMISSION_DENIED`) — a real, spec-legitimate answer to the same
  requirement given what this SDK version actually exposes.

## Verification

[`../../verification/payroll`](../../verification/payroll) is a real
`ballerina/a2a` `GrpcClient` script. All 6 structural checks pass today
with **no Anthropic key required** (the admin token is independent):

```sh
cd verification/payroll
bal run --sticky
```

The one check that needs the model to actually answer (`sendMessage`'s
response content) is explicitly marked deferred — see
[Phase 9 in the implementation plan](../../docs/implementation-plan.md).

Requires `ballerina/a2a` in your local Ballerina package repository
(`bal pack && bal push --repository=local` from the `a2a-ballerina`
checkout).
