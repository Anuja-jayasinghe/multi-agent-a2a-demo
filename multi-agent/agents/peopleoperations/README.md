# PeopleOperations Agent (HR)

A real A2A listener agent for WSO2 People Operations — policy Q&A,
onboarding, and staff-only case escalation via a genuinely gated extended
agent card. Confirmed WSO2-internal name — see
[`../../NAMING.md`](../../NAMING.md).

Real Anthropic backing via LangGraph from the start — no stub model. See
the ["Everything real, nothing simulated"](../../CLAUDE.md) rule for why.

## Stack

Python 3.12 · `uv` · [LangGraph](https://langchain-ai.github.io/langgraph/)
(`create_react_agent` + `MemorySaver`) · real `ChatAnthropic`
(`langchain-anthropic`) · [`a2a-sdk`](https://pypi.org/project/a2a-sdk/) ·
JSON-RPC binding · port 8002.

## Run it

```sh
cd agents/peopleoperations
uv sync
export ANTHROPIC_API_KEY=...        # required for policy Q&A / onboarding
export PEOPLEOPS_STAFF_TOKEN=...    # required to test authenticated extended-card access
uv run __main__.py
```

Without `ANTHROPIC_API_KEY`, the agent boots and serves its card correctly,
but every real request fails gracefully with a typed error — verified, see
below. `PEOPLEOPS_STAFF_TOKEN` is independent of the LLM key and can be set
without it — the extended-card gating below works today with no key at all.

Agent card: `http://127.0.0.1:8002/.well-known/agent-card.json`

## What it does

- **Policy Q&A (`sendMessage`)** — real Claude answering from
  fictional-but-WSO2-styled HR reference text (`agent.py`): leave policy,
  benefits. No task created.
- **Onboarding (`sendStreamingMessage` + `subscribeToTask`)** — asking to
  onboard a named hire makes the real LLM call three real tool functions
  in sequence (`tools.py`: `provision_laptop`, `assign_desk`,
  `enroll_benefits`), each a genuine in-memory state change. The LLM's own
  tool-calling *is* the progress narration streamed to the client — there's
  no separate executor-authored script for it. Genuinely interruptible via
  `cancelTask`, genuinely resumable via `subscribeToTask`.
- **`getExtendedAgentCard`** — gated by a real (if minimal) bearer-token
  check (`auth.py`): an unauthenticated request gets the public 2-skill
  card; a request with `Authorization: Bearer $PEOPLEOPS_STAFF_TOKEN` gets
  a 3rd skill, `case-escalation`, that the public card never lists. This is
  pure card-serving logic — no LLM involved, fully verified without a key.

Policy Q&A and onboarding share one code path deliberately (like DigiOps's
FAQ/ticket split) — the real LLM's own tool-calling decides which happens.

## Verification

[`../../verification/peopleoperations`](../../verification/peopleoperations)
is a real `ballerina/a2a` client script. Card and auth-gating checks pass
today with **no Anthropic key required** (the staff token is independent):

```sh
cd verification/peopleoperations
bal run --sticky
```

Checks that need the model to actually answer are explicitly marked
deferred — see [Phase 9 in the implementation plan](../../docs/implementation-plan.md).

Requires `ballerina/a2a` in your local Ballerina package repository
(`bal pack && bal push --repository=local` from the `a2a-ballerina` checkout).
