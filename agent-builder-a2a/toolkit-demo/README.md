# A2A toolkit demo agents

Three A2A server agents for demonstrating `ai:A2aToolKit` and **Add Tool → Use Agent → A2A Agent** in Agent Builder.

- All three run from one Ballerina package on `ballerina/a2a` 0.8.0.
- Each has a full Agent Card: provider, documentation link, skills with examples, and input and output modes.
- Answers are fixed (demo data), so they need no model key and always reply the same way.

| Agent | URL | Credential | Ask it |
|---|---|---|---|
| Weather Agent | `http://localhost:9201` | none | "Will it rain in Kandy this weekend?" |
| Currency Agent | `http://localhost:9202` | HTTP Basic | "Convert 150 USD to LKR" |
| City Events Agent | `http://localhost:9203` | Bearer (JWT) | "What's on in Galle this weekend?" |

The cities they know: Colombo, Kandy, Galle, London, Paris, Tokyo, New York, San Francisco.

## Run

Double-click `Run Toolkit Demo Agents.command`, or run:

```bash
./run.sh
```

On the first run it writes two local files, both gitignored:

- `Config.toml`: the Basic user and the JWT signing secret.
- `demo-credentials.txt`: the secret to paste for each agent.

`./run.sh --new-credentials` makes new ones. Ctrl+C stops all three agents.

## Show it in Agent Builder

1. In the agent, click **Add Tool → Use Agent → A2A Agent**.
2. Enter the Agent URL, for example `"http://localhost:9201"`, then click **Fetch Card**.
3. The card shows what the agent does and the credential it needs:
   - **Weather:** none, so no Secret is asked for.
   - **Currency:** Basic.
   - **City Events:** Bearer.
4. For Currency and City Events, paste the Secret from `demo-credentials.txt`, with its quotes, in Expression mode.
5. Click **Add as Tool**.

The toolkit is named after the card: `weatherAgent`, `currencyAgent`, `cityEventsAgent`.

The form writes the secret into `connections.bal` as a string. For anything beyond a local demo, make it a configurable instead.

## How the auth works

The listener checks credentials with `RestListenerConfiguration.auth`:

- Currency uses a file user store, so Basic works against the users in `Config.toml`.
- City Events uses a JWT validator with issuer `toolkit-demo` and audience `city-events-agent`.

Each card's `securitySchemes` and `securityRequirements` are derived from that config. The card itself stays public, and every A2A call needs the credential: a missing or wrong one gets a 401.
