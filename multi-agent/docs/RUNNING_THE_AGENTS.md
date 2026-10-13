# Starting the agents (before you test with the client)

Two ways to run this whole thing. Pick one — you don't need both at
once, and they use the same ports so only one can run at a time.

| | Local processes | Docker |
|---|---|---|
| What it is | Five real processes + the orchestrator, running directly on your Mac | The same six things, each in its own container, via Rancher Desktop |
| Good for | Quick iteration, BI Run/Debug | Testing it the way it'd actually deploy |
| Setup effort | None — scripts handle it | One-time build step |

Either way, **the five downstream agents (Parking, DigiOps,
PeopleOperations, Payroll, Travel & Expense) have to be up before you
test the client** — the orchestrator/chat won't have anyone to talk to
otherwise.

## Before either option

```sh
cp .env.example .env   # then paste a real ANTHROPIC_API_KEY into it
```
`.env` is git-ignored — never commit it. Without a real key, agents
still start and answer "who's up" style questions, but real chat
requests fail gracefully instead of giving a real answer.

---

## Option A — local processes, no Docker

```sh
./scripts/start-all.sh
```
This starts all five agents *and* the orchestrator, waiting for each
to actually be ready before starting the next. When it's done printing,
everything's up:

```
Parking:            http://127.0.0.1:8000
DigiOps:            http://127.0.0.1:8001
PeopleOperations:   http://127.0.0.1:8002
Payroll:            http://127.0.0.1:8003 (grpc: 9003)
Travel & Expense:   http://127.0.0.1:8004
Orchestrator:       http://127.0.0.1:9090 (webhook receiver), http://127.0.0.1:8090 (chat)
```

**Test the client:**
```sh
curl -s http://127.0.0.1:8090/concierge/chat \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"test","message":"is there parking available today?"}'
```

**Shut it down when done:**
```sh
./scripts/stop-all.sh
```

**Testing/chatting through WSO2 Integrator: BI instead of curl?**
Run `./scripts/start-agents.sh` instead of `start-all.sh` — it starts
just the five agents and leaves the orchestrator for BI's own
Run/Debug or chat panel to start. BI's Run button doesn't start the
five agents for you, so this step still has to happen first, manually.

Logs land in `logs/<name>.log`; PIDs are tracked in `.pids/` so
`stop-all.sh` knows what to kill.

---

## Option B — Docker (via Rancher Desktop)

Rancher Desktop needs to already be **open and running** (check the
app, or the whale icon in your menu bar) — it's what actually runs the
containers. If `docker` isn't a recognized command in your terminal,
add it to your PATH once per shell session:
```sh
export PATH="$HOME/.rd/bin:$PATH"
```

**One-time step, only needed again if `ballerina/a2a` itself changes:**
```sh
./orchestrator/prepare-docker-build.sh
```
`ballerina/a2a` isn't published anywhere Docker can fetch it from, so
this copies your local copy into a staging folder the orchestrator's
Docker build can see.

**Build and start everything:**
```sh
docker compose up -d --build --wait
```
- `-d` = run in the background, don't block your terminal
- `--build` = rebuild any image whose source changed
- `--wait` = don't return control until every container reports healthy

First build takes a few minutes (downloading base images, compiling).
After that, rebuilds are much faster — only what changed gets rebuilt.

**Check everything's actually healthy:**
```sh
docker compose ps
```
Every row should say `healthy`, not just `running`.

**Test the client** — same command as local, same port:
```sh
curl -s http://127.0.0.1:8090/concierge/chat \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"test","message":"is there parking available today?"}'
```

**See what's happening / debug a container:**
- In the Rancher Desktop app → **Containers** tab: click any container
  for live logs, or to stop/restart just that one.
- From the terminal: `docker compose logs -f <service>` (e.g. `parking`,
  `orchestrator`).

**Shut it down when done:**
```sh
docker compose down
```
This stops and removes the containers, but keeps the built images —
next `docker compose up` (no `--build` needed) is fast.

### If something goes wrong

- **"Cannot connect to the Docker daemon"** — Rancher Desktop's backend
  needs a moment after opening the app, or after a settings change. Wait
  ~30s and retry. If it stays stuck, `rdctl set --virtual-machine.memory-in-gb 6 --virtual-machine.number-cpus 4`
  forces a clean backend restart (this repo's build is genuinely heavy —
  two Java builds, three Python builds, and a Ballerina build; the
  default 2 CPU / 4GB allocation can choke building all of them at once).
- **A build step times out fetching an image** — usually transient
  network flakiness, especially right after Rancher Desktop restarts.
  Just re-run the same `docker compose up -d --build --wait` command.
- **Chat requests fail but the agents' own `/well-known/agent-card.json`
  works** — check `.env` actually has a real `ANTHROPIC_API_KEY` and that
  you built the images *after* setting it (`docker compose up --build`
  again after editing `.env`).

---

## Either way — confirming the agents themselves are actually up

Each downstream agent serves a real Agent Card once it's ready:
```sh
curl -s http://127.0.0.1:8000/.well-known/agent-card.json   # Parking
curl -s http://127.0.0.1:8001/.well-known/agent-card.json   # DigiOps
curl -s http://127.0.0.1:8002/.well-known/agent-card.json   # PeopleOperations
curl -s http://127.0.0.1:8003/.well-known/agent-card.json   # Payroll
curl -s http://127.0.0.1:8004/.well-known/agent-card.json   # Travel & Expense
```
A real JSON response (not "connection refused") means that agent's
ready for the orchestrator to talk to.

For what each agent can actually *do* once it's up, see
[`AGENT_CHEAT_SHEET.md`](AGENT_CHEAT_SHEET.md).

## Watching every agent work, live

Want to actually *see* each agent receive a task, work on it, and send
the response back, instead of just knowing it's running? Both modes
have a script that opens one Terminal.app window per agent (macOS
only) so each window shows that agent's own live output:

```sh
./scripts/watch-agents-local.sh    # local processes — starts them itself
./scripts/watch-agents-docker.sh   # Docker — watches an already-running stack
```

`watch-agents-local.sh` starts all six processes itself (building each
one first if needed) — don't run `start-all.sh` first, it'd just
conflict on the same ports. `watch-agents-docker.sh` only tails logs —
run `docker compose up -d --build --wait` first.

First run may prompt macOS for permission to let Terminal be
controlled by scripts — allow it, that's what opens the windows.
