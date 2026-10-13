# Research

Investigations done outside the numbered implementation-plan phases —
architectural questions that needed real evidence (source code, official
docs, or both) rather than a guess, before a decision got made. Each file
here cites exactly what was checked and where, per the standing rule:
confirm by real evidence, never assume.

| Doc | Question | Outcome |
|---|---|---|
| [`remote-agent-integration-patterns.md`](remote-agent-integration-patterns.md) | How do real frameworks wire a remote/A2A agent into an orchestrator — system-prompt text, or tools? | Tools, universally. Confirmed our existing `orchestrator/agent_tools.bal` already matches — no redesign needed |
| [`wso2-integrator-bi-compatibility.md`](wso2-integrator-bi-compatibility.md) | Is `orchestrator/` (a plain `bal`-CLI Ballerina package) compatible with WSO2 Integrator: BI, the platform this will actually be demoed through? | Yes — but BI only renders a chat-testable "AI Agent Service" for an `ai:Listener`/`ai:ChatService`, which `concierge` didn't have; added `chat_service.bal` to fix it |
| [`a2a-client-and-demo-round-check.md`](a2a-client-and-demo-round-check.md) | Full live round check after Phase 13 Part 3: does the client + all 5 agents actually still work together? | All 4 findings addressed: stale locally-published `ballerina/a2a` package, an orchestrator-test-currency gap from PR #35, a real spec-vs-real-server content-type incompatibility (fixed via negotiation in `a2a-ballerina` PR #45), and reduced flaky-fixture-name odds |
