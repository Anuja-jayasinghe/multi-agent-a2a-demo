# Employee Concierge: one orchestrator, five agents, three transports, three languages

> Source: [Employee Concierge Architecture](https://claude.ai/code/artifact/4630c2c1-4859-48ad-950e-01888a74ce4d)
> (approved proposal artifact, `ballerina/a2a` end-to-end demo architecture)
>
> **As built (Phases 1–10 complete):** matches this document, with three
> corrections applied below — PeopleOperations/DigiOps replacing the
> generic HR/IT Helpdesk names (confirmed WSO2-internal names, see
> [`NAMING.md`](../NAMING.md)), three agents (not just Payroll)
> registering real push-notification webhooks back to the orchestrator,
> and Parking converted to real LLM-backed (Google ADK + Anthropic,
> same as DigiOps) after live BI testing showed its original
> keyword-only matching couldn't answer general questions like "is
> anything free?" — it no longer proves the "A2A without an LLM" point
> the original proposal below describes it for. Payroll, Parking, and
> Travel & Expense still carry generic names, pending confirmation. The
> system is three languages, not two — Python and Java on the agent
> side, Ballerina for the orchestrator — corrected in the title above.

A single client-side orchestrator, built on Ballerina and `ballerina/a2a`, fields
employee requests and routes them to five independent listener agents — each a
separately deployable A2A server, deliberately built in different languages and
frameworks, so the demo proves real interoperability rather than one framework
talking to itself.

## Architecture

The orchestrator is the only thing employees talk to. Every specialist behind it
is reached purely over the open A2A protocol — the orchestrator has no other
integration with any of them.

```mermaid
flowchart LR
    Employee((Employee))
    Orchestrator["Employee Concierge<br/>Ballerina + ballerina/ai<br/>ballerina/a2a client"]
    HR["PeopleOperations Agent - HR<br/>Python - LangGraph<br/>policy Q and A - onboarding"]
    Payroll["Payroll Agent<br/>Java - a2a-java SDK<br/>payslips - corrections"]
    Parking["Parking Manager Agent<br/>Python - Google ADK<br/>spot lookup - reservations"]
    IT["DigiOps Agent - IT Helpdesk<br/>Python - Google ADK<br/>tickets - live incidents"]
    Travel["Travel and Expense Agent<br/>Java - a2a-java SDK<br/>bookings - claims"]

    Employee -- asks --> Orchestrator
    Orchestrator -- "A2A - JSON-RPC" --> HR
    Orchestrator -- "A2A - gRPC" --> Payroll
    Orchestrator -- "A2A - REST" --> Parking
    Orchestrator -- "A2A - JSON-RPC" --> IT
    Orchestrator -- "A2A - REST" --> Travel
    Parking -. "webhook POST on task completion" .-> Orchestrator
    Payroll -. "webhook POST on task completion" .-> Orchestrator
    Travel -. "webhook POST on task completion" .-> Orchestrator
```

Five independently deployable agents sit behind the orchestrator, each a genuine
A2A server — different language, different framework, different transport
binding — reached purely through the open protocol. The three reversed edges are
real push-notification webhooks the agents call back into the orchestrator's own
receiver (`orchestrator/webhook_receiver.bal`), not the orchestrator polling them —
built in Phase 6, ahead of this doc's original single-Payroll sketch.

## The orchestrator

**Employee Concierge** is the single agent every employee actually talks to — a
chat-style front end backed by a Ballerina `ai:Agent`, reaching every specialist
behind it purely through `ballerina/a2a`.

Stack: **Ballerina**, **ballerina/ai** (or WSO2 Integrator: BI), **ballerina/a2a client**.

The LLM decides which specialist a given request belongs to; `ballerina/a2a` is
the only thing that actually talks to it. As built, each of the five specialists
is a fixed local URL the orchestrator resolves once at startup (`agent_tools.bal`)
— real service discovery/registration for a genuine multi-host deployment remains
future work beyond this local-process demo.

## The five listener agents

Every agent is a real, independently running A2A server — not a stub. Language,
framework, and transport binding are chosen so the five together prove every one
of the client's 11 operations and all three transport bindings, with genuine
multi-language interoperability.

### PeopleOperations Agent (HR)
**Stack:** Python · LangGraph · JSON-RPC

Policy questions answered instantly; onboarding is a real multi-step, multi-day
checklist streamed live.

**Proves:** `sendMessage`, `sendStreamingMessage`, `subscribeToTask`, `getExtendedAgentCard`

### Payroll Agent
**Stack:** Java · a2a-java SDK · Quarkus · gRPC

A payslip-correction request is a genuine reviewed task, and its resolution is
the clearest case for a push notification of the whole demo.

**Proves:** `getTask`, `cancelTask`, `listTasks`, `createTaskPushNotificationConfig`,
`getTaskPushNotificationConfig`, `listTaskPushNotificationConfigs`,
`deleteTaskPushNotificationConfig`, `getExtendedAgentCard`

### Parking Manager Agent
**Stack:** Python · Google ADK + real Anthropic backing · REST (HTTP+JSON)

Originally built with no agent framework at all, proving A2A works fine
without an LLM in the loop — converted to real LLM backing after live
testing showed keyword-only matching couldn't handle general questions
like "is anything free?". Task-lifecycle mechanics (the reservation
window, cancelTask) are unchanged, still plain deterministic Python.

**Proves:** `sendMessage`, `cancelTask`, `createTaskPushNotificationConfig`,
`deleteTaskPushNotificationConfig`

### DigiOps Agent (IT Helpdesk)
**Stack:** Python · Google ADK · JSON-RPC

FAQ answers alongside a real ticket lifecycle, plus a live incident
investigation you can disconnect from and resume.

**Proves:** `sendMessage`, `getTask`, `cancelTask`, `listTasks`,
`sendStreamingMessage`, `subscribeToTask`

### Travel & Expense Agent
**Stack:** Java · a2a-java SDK · REST (HTTP+JSON)

An expense claim moves through review over days — cancelable, listable, and
worth a notification when reimbursed.

**Proves:** `getTask`, `cancelTask`, `listTasks`, `createTaskPushNotificationConfig`,
`getTaskPushNotificationConfig`

## Full coverage, one system

Every one of the client's 11 operations and all three transport bindings is
exercised by at least one agent above — most by more than one, since a real
employee's day naturally touches several.

| Operation | Exercised by |
|---|---|
| `sendMessage` | PeopleOperations · Parking · DigiOps |
| `sendStreamingMessage` | PeopleOperations (onboarding) · DigiOps (incident) |
| `getTask` | Payroll · DigiOps · Travel & Expense |
| `cancelTask` | Payroll · Parking · DigiOps · Travel & Expense |
| `subscribeToTask` | PeopleOperations · DigiOps |
| `listTasks` | Payroll · DigiOps · Travel & Expense |
| `createTaskPushNotificationConfig` | Payroll · Parking · Travel & Expense |
| `getTaskPushNotificationConfig` | Payroll · Travel & Expense |
| `listTaskPushNotificationConfigs` | Payroll |
| `deleteTaskPushNotificationConfig` | Payroll · Parking |
| `getExtendedAgentCard` | PeopleOperations (staff-only escalation skill) · Payroll (admin-only cross-employee adjustment skill) |
