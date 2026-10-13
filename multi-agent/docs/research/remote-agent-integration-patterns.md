# How real frameworks wire remote/A2A agents into an orchestrator

**Question:** should the orchestrator's five downstream agents be handed
to the concierge Agent as plain endpoint URLs embedded in the system
prompt, or as tools? Don't assume — confirm against how real frameworks
actually do this.

**Decision: tools.** `orchestrator/agent_tools.bal` already does this
(`@ai:AgentTool`-annotated functions, each holding a real `a2a:Client`)
— confirmed to match every framework checked below, so no redesign was
needed.

## Google ADK — `RemoteA2aAgent`, a native sub-agent

Real source, inspected locally (installed in `agents/digiops/.venv`):
`google/adk/agents/remote_a2a_agent.py`.

```python
class RemoteA2aAgent(BaseAgent):
  def __init__(self, name, agent_card: Union[AgentCard, str], ...):
```

`RemoteA2aAgent` subclasses `BaseAgent` — the same base class a local
agent inherits from — and gets added to a parent's `sub_agents` list.
From the parent's routing logic, a remote A2A agent is indistinguishable
from a local one. `agent_card` accepts a URL, but that URL is used to
resolve the real card and build a real `A2AClient`; it's never pasted
into a prompt. The remote agent's `description` auto-populates from its
card (line 393: `if not self.description and agent_card.description`)
and becomes what the parent LLM sees when deciding whether to route to
it — the routing signal comes from a structured object, not raw text a
developer typed in.

## LangGraph / LangChain — no native sub-graph support; the ecosystem converged on tools

Checked the real forum thread:
[Feature Request: Native Support for A2A Protocol (Remote Agents as Sub-Graphs)](https://forum.langchain.com/t/feature-request-native-support-for-a2a-protocol-remote-agents-as-sub-graphs/1521).
**Rejected/unfulfilled.** A maintainer (catherine-langchain) pointed to
LangGraph Server's A2A endpoint; a community follow-up clarified that
endpoint is messaging-only — "it does not share the state. So the remote
agent is not first-class nodes/sub-graphs" as the request asked for.
Stated workarounds: LangGraph Server's A2A endpoint (messaging only),
manual custom handoff logic, or **wrap remote agents as tools**.

Two independent real packages confirm the tool pattern is what's
actually used in practice:

- `python-a2a`'s `LangChainBridge` (docs:
  `python-a2a.readthedocs.io/en/latest/guides/langchain.html`):
  ```python
  from python_a2a.langchain import LangChainBridge
  langchain_tool = LangChainBridge.agent_to_tool("http://localhost:5002")
  tools = [a2a_tool, search_tool, wiki_tool]
  agent = create_react_agent(llm, tools, prompt)
  ```
  The exact `create_react_agent(llm, tools, prompt)` call our own
  PeopleOperations agent already uses.

- `a2a-langchain-adapters` (PyPI): `A2ARunnable.from_agent_url(url)`,
  described as exposing "agents as LangChain tools for function calling."

## WSO2 Integrator: BI — explicit on this exact point

BI's own docs,
[Integrating Agents with External Endpoints](https://bi.docs.wso2.com/integration-guides/ai/agents/integrating-agents-with-external-endpoints/):

> "External endpoints are never embedded as plain text in system
> prompts."

BI uses a two-layer **Connection → Tool** abstraction for any external
service (the worked example is Gmail/Google Calendar via BI's prebuilt
connectors). No A2A-specific connector exists in BI yet — checked the
full Agents section (Chat Agents, Inline Agents, MCP Servers, External
Endpoints); MCP has a dedicated integration guide, A2A doesn't. A remote
A2A agent would go through BI's general **"Tools from functions"**
mechanism instead.

Confirmed BI's own tooling is built around exactly this, with zero web
dependency — grepped the installed `wso2.ballerina` extension's bundled
JS directly:

```
e.BIAgentToolForm="Add Agent Tool SKIP"
t.createAIAgent={method:`${n}/createAIAgent`}
t.updateAIAgentTools={method:`${n}/updateAIAgentTools`}
```

A real **"Add Agent Tool"** UI action, wired to `createAIAgent`/
`updateAIAgentTools` Language Server calls — operating on the same
`ballerina/ai` module and the same `@ai:AgentTool` annotation
`orchestrator/agent_tools.bal` already uses.

## Conclusion

| Platform | Native "remote agent" concept? | Actual pattern | Evidence |
|---|---|---|---|
| Google ADK | Yes — `RemoteA2aAgent(BaseAgent)` | Sub-agent, first-class node | Real source, inspected locally |
| LangGraph/LangChain | No — feature request rejected | Tool (`LangChainBridge.agent_to_tool`, `A2ARunnable`) | Forum thread + two real packages |
| WSO2 Integrator: BI | No A2A-specific connector yet | Tool (Connection → Tool, or "Tools from functions") | BI's own docs + own extension code |
| This project | — | `@ai:AgentTool` functions in `agent_tools.bal` | Already built this way |

All three real platforms converge on the same answer: **tools, not
system-prompt text.** `orchestrator/agent_tools.bal` already matches it.

## Still open

Whether BI's visual "Add Agent Tool" / Agent Tools panel *displays* the
five existing `@ai:AgentTool` functions correctly when `orchestrator/` is
opened, versus its wizard only knowing how to *generate* a new function
from scratch — needs a real look in the BI Visualizer GUI, which needs a
human at the keyboard (no CLI/scripted way to drive VS Code's webview
UI). Not yet done.
