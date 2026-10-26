# Agent Builder A2A demo agents

Agents used to try the A2A server trigger and the "Use Remote Agent" tool in WSO2 Agent Builder (a local concept build,
branch `demo/a2a-agent-builder`, never pushed upstream). Each folder is a Ballerina package that uses an Anthropic model.

| Package | Role | Notes |
|---|---|---|
| `recipe` | A2A **server**, port 9096 | Published with Add Trigger → A2A Server. Suggests a dinner recipe from ingredients. |
| `pantry` | A2A **client** | Calls `recipe` through Add Tool → Use Remote Agent; has an Agent Chat trigger. |
| `meals` | A2A server, port 9097 | Card with provider and documentation fields; all 10 operations. |
| `desserts` | Agent only | Fresh agent used to try publishing from the UI. |
| `tripplanner`, `concierge` | Server and client | The first pair, from before the UI work. |

## Run an agent and see its card

Double-click `Run Recipe Agent (show card).command`, or run `./run-agent.sh [package]` (default `recipe`). It builds the package,
starts it, prints the Agent Card it serves and opens `http://localhost:9096/.well-known/agent-card.json` in the browser. The card needs
no model call, so a placeholder key is enough; if `a2a-library-testing/.env` holds a key it is used. Ctrl+C stops the agent.

## Run it by hand

Put a model key in each package's `Config.toml` (gitignored): `anthropicApiKey = "..."`, or use `BAL_CONFIG_DATA`.

```bash
cd recipe && bal run          # serves http://localhost:9096/.well-known/agent-card.json
cd pantry && bal run          # POST http://localhost:9090/pantry-assistant/chat
```

## Open Agent Builder with the A2A screens

Double-click `Open Agent Builder (A2A).command`, or run `./agent-builder-a2a.sh [folder]`. It uses its own VS Code profile
and the VSIX built from the demo branch (see `a2a-learnings/learnings/agent-builder/running-the-agent-builder-build.md`
and `a2a-demo-build.md`). Run with `--reinstall` after rebuilding the VSIX.
