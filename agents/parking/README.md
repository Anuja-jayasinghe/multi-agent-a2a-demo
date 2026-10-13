# Parking Manager Agent

A real A2A listener agent for WSO2 office parking availability and
reservations. Generic name for now — see [`../../NAMING.md`](../../NAMING.md)
for the pending WSO2-internal rename.

Originally built with **no LLM framework at all**, per the architecture's
original goal of proving A2A works correctly without an LLM in the loop.
Converted to real Google ADK + Anthropic backing so it genuinely
understands free-form availability questions and asks a real clarifying
question when a reservation request doesn't name a clear spot — the
Task-lifecycle mechanics below are otherwise unchanged, still plain
deterministic Python.

## Stack

Python 3.12 · `uv` · [`a2a-sdk`](https://pypi.org/project/a2a-sdk/) 1.2.1 ·
[Google ADK](https://google.github.io/adk-docs/) + real Anthropic backing ·
REST (HTTP+JSON) binding · port 8000.

## Run it

```sh
cd agents/parking
uv sync
export ANTHROPIC_API_KEY=...   # required for real availability/reservation answers
uv run __main__.py
```

Agent card: `http://127.0.0.1:8000/.well-known/agent-card.json`

## What it does

- **`sendMessage`** — an availability question ("is spot A01 free?", or a
  general one like "is anything free?") is answered directly as a plain
  `Message`, no task created — the real LLM call decides whether to check
  a specific spot or list every free one.
- **Task lifecycle** — "reserve spot A01" creates a task immediately (a
  real LLM call then extracts which spot, or asks a real clarifying
  question if none was named clearly) that spends a few seconds in
  `WORKING` ("checking with facilities") before resolving to `COMPLETED`
  (spot reserved) or `REJECTED` (already taken). That window exists
  specifically so `cancelTask` has something real to interrupt.
- **`cancelTask`** — cancels a pending reservation mid-flight; correctly
  fails with `TaskNotCancelableError` against an already-terminal task.
- **Push-notification config CRUD** — `createTaskPushNotificationConfig`
  and `deleteTaskPushNotificationConfig` on a reservation's task. Actual
  webhook *delivery* is orchestrator-side work (Phase 6 of the
  [implementation plan](../../docs/implementation-plan.md)); this proves
  the config CRUD surface.

## Mock data

A small fixed set of spots at WSO2's Colombo HQ (`data.py`) — real, public,
harmless fact used for flavor; the spots and reservations themselves are
entirely fictional.

## Verification

[`../../verification/parking`](../../verification/parking) is a real
`ballerina/a2a` client script that exercises every operation above against
the running agent — no mocks. Run the agent first, then:

```sh
cd verification/parking
bal run --sticky
```

Requires `ballerina/a2a` available in your local Ballerina package
repository (`bal pack && bal push --repository=local` from the
`a2a-ballerina` checkout).
