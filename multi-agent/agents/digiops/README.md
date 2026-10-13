# DigiOps Agent (IT Helpdesk)

A real A2A listener agent for WSO2 IT support — FAQs, hardware tickets, and
live incident investigation. Confirmed WSO2-internal name — see
[`../../NAMING.md`](../../NAMING.md).

Real Anthropic backing via Google ADK from the start — no stub model. See
the ["Everything real, nothing simulated"](../../CLAUDE.md) rule for why.

## Stack

Python 3.12 · `uv` · [Google ADK](https://google.github.io/adk-docs/) (`LlmAgent`
+ `AnthropicLlm`) · [`a2a-sdk`](https://pypi.org/project/a2a-sdk/) · JSON-RPC
binding · port 8001.

## Run it

```sh
cd agents/digiops
uv sync
export ANTHROPIC_API_KEY=...   # required for FAQ/ticket/incident handling
uv run __main__.py
```

Without the key, the agent boots and serves its card correctly, but every
real request fails gracefully with a typed error (verified — see below) —
that's expected until Phase 9.

Agent card: `http://127.0.0.1:8001/.well-known/agent-card.json`

## What it does

- **FAQ Q&A (`sendMessage`)** — VPN/password-reset style questions, answered
  by the real LLM from fictional-but-WSO2-styled IT reference facts
  (`agent.py`). No task created.
- **Hardware tickets (task lifecycle)** — the same LLM call can instead call
  `create_ticket`/`get_ticket` (`tickets.py`, real in-memory tool functions)
  when the request is a hardware request rather than a question. Proves
  `getTask`/`cancelTask`/`listTasks`.
- **Incident investigation (`sendStreamingMessage` + `subscribeToTask`)** —
  staged, executor-controlled progress narration ("checking network
  logs...") precedes a real LLM call for the actual diagnosis. Genuinely
  interruptible via `cancelTask` at any staged step, and genuinely
  resumable via `subscribeToTask` after a real disconnect (not just one
  uninterrupted stream).

FAQ and ticket handling share one code path deliberately — the real LLM's
own tool-calling decides which happens, there's no separate branch pretending
to route between them.

## Verification

[`../../verification/digiops`](../../verification/digiops) is a real
`ballerina/a2a` client script. Structural checks (card, streaming mechanics,
graceful-failure-without-a-key) pass today with **no API key required**:

```sh
cd verification/digiops
bal run --sticky
```

Checks that need the model to actually answer correctly are explicitly
marked deferred and get exercised for real once the key is supplied — see
[Phase 9 in the implementation plan](../../docs/implementation-plan.md).

Requires `ballerina/a2a` in your local Ballerina package repository
(`bal pack && bal push --repository=local` from the `a2a-ballerina` checkout).
