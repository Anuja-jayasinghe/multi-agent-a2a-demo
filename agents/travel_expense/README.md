# Travel & Expense Agent

A real A2A listener agent for WSO2 Travel & Expense — expense claims and
travel policy questions. Generic name for now — see
[`../../NAMING.md`](../../NAMING.md) for what's still pending.

Real Anthropic backing via langchain4j from the start — no stub model.
See the ["Everything real, nothing simulated"](../../CLAUDE.md) rule for
why.

## Stack

Java 17 · Maven · Quarkus · [`a2a-java`](https://github.com/a2aproject/a2a-java)
SDK 1.4.0.Final (REST binding — the one agent in the demo exercising
`ballerina/a2a`'s `RestClient`) · `quarkus-langchain4j-anthropic`
(`@RegisterAiService`) · port **8004**.

Two real integration fixes carried over from Payroll's build
(`agents/payroll`), applied from the first commit rather than
rediscovered: `quarkus.http.http2=false` (ballerina/http's client
defaults to HTTP/2 cleartext prior-knowledge negotiation, which doesn't
interop with Vert.x's h2c handling — every A2A operation here is over
this same plain HTTP port, not just card discovery, so this agent would
hit it on every call) and `protobuf-java`/`protobuf-java-util` pinned to
`4.34.2` (the a2a-java 1.4.0.Final spec types are protobuf messages
regardless of transport, not just for gRPC — reproduced the
`NoClassDefFoundError` once before pinning, to confirm it wasn't
gRPC-specific).

## Run it

```sh
cd agents/travel_expense
mvn -DskipTests -Dquarkus.analytics.disabled=true package
export ANTHROPIC_API_KEY=...   # required for real expense/policy answers
java -jar target/quarkus-app/quarkus-run.jar
```

Without `ANTHROPIC_API_KEY`, the agent boots and serves its card
correctly, but every real request fails gracefully with a typed error —
verified, see below.

Agent card: `http://127.0.0.1:8004/.well-known/agent-card.json`

## What it does

- **Travel/expense FAQs and claim filing (`sendMessage`)** — real Claude
  (via langchain4j) answering from fictional-but-WSO2-styled reference
  text (`TravelExpenseAgent.java`'s system prompt): per-diem rates,
  receipt threshold, entertainment-approval rule, filing deadline,
  approval SLA. When the request describes an expense to claim, the model
  calls a real tool (`TravelExpenseTools.fileExpenseClaim`) that mutates
  real in-memory state and returns a claim ID; a follow-up status check
  calls `getClaimStatus`.
- **Task lifecycle (`getTask`/`cancelTask`/`listTasks`)** — every request
  drives a real A2A task through `submit -> startWork -> complete`, or
  fails it genuinely if the underlying LLM call errors.
- **Push-notification config: create + get** — deliberately narrower
  scope than Payroll, which already proved full CRUD (including
  `list`/`delete`) against the same `InMemoryPushNotificationConfigStore`
  auto-wiring. This agent's job is proving the REST binding's config
  surface, not re-proving CRUD. Pure data, no LLM involved.

## Verification

[`../../verification/travel_expense`](../../verification/travel_expense)
is a real `ballerina/a2a` `RestClient` script. All 5 structural checks
pass today with **no Anthropic key required**:

```sh
cd verification/travel_expense
bal run --sticky
```

The one check that needs the model to actually answer (`sendMessage`'s
response content) is explicitly marked deferred — see
[Phase 9 in the implementation plan](../../docs/implementation-plan.md).

Requires `ballerina/a2a` in your local Ballerina package repository
(`bal pack && bal push --repository=local` from the `a2a-ballerina`
checkout).
