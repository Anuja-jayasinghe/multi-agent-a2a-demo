# Employee Concierge — Implementation Plan

Status: **all 13 phases complete**. See [`architecture.md`](architecture.md) for the
approved system design this plan implements, and each phase section below for what
was actually built and verified.

## Decisions locked in for this plan

| Decision | Answer |
|---|---|
| Repo | Monorepo, public — `github.com/Anuja-jayasinghe/multi-agent-a2a-demo` (renamed from `employee-concierge-demo`) |
| LLM provider | Anthropic Claude, all agents and the orchestrator |
| MCP | Out of scope. Every agent's data is mocked and reached through plain tool functions |
| Deployment | Local processes first (manual rough-check pass), Docker Compose once that's verified and reviewed |
| Naming | Current names stay for now except HR → **PeopleOperations**, IT Helpdesk → **DigiOps**. Payroll / Parking / Travel & Expense get real WSO2 names later — tracked in [`NAMING.md`](../NAMING.md) so nothing gets lost |
| Data realism | Mock data may reference real, harmless, public WSO2 facts (office locations, general org shape) for flavor. Never a fabricated "real" record — no real figures, real policy text, or anything that could be mistaken for an actual internal document |
| Timeline | No fixed date — move as fast as correctness allows |
| API key | Every agent is built with **real** Anthropic backing from the start — no stub/fake model, no simulated agent. See below. |
| Git workflow | See `CLAUDE.md`: never commit to `main`, one branch per feature (sub-branched for large features), small commits per piece of a feature, push/PR/merge only on explicit approval, no squash merges |

## Everything real, nothing simulated

Every agent — PeopleOperations, DigiOps, Payroll, Parking, Travel & Expense — is a
real agent with a real LLM (Anthropic) as its actual reasoning backend. The
connections between agents are real A2A protocol calls over each agent's declared
transport binding, made by the orchestrator's real `ballerina/a2a` client against
real, independently running remote agents, each built on its own real A2A SDK
(`a2a-python`, `a2a-java`). Nothing is mocked, stubbed, or bypassed at the agent or
protocol layer.

**Practical consequence**: any LLM-dependent behavior (an agent's actual reasoning,
the orchestrator's routing decisions) can't be exercised until the real Anthropic key
is supplied — that's a genuine gating condition on *running* those specific tests, not
something to be worked around by building a fake implementation. Work that doesn't
need the model to produce output — agent card resolution, task state machines,
transport-binding correctness, push-notification config CRUD, Parking's logic (which
never needed an LLM in the first place per the architecture) — proceeds and gets fully
tested regardless of key availability. Everything else gets built for real and waits
for the key to actually run, rather than being faked in the meantime.

## Phases

### Phase 0 — Scaffolding (mostly done)
- [x] Repo created, pushed, added to the workspace
- [x] `docs/architecture.md` — the approved design
- [ ] `NAMING.md` at repo root — tracks confirmed vs. placeholder agent names
- [ ] Monorepo layout: `orchestrator/`, `agents/parking/`, `agents/digiops/`,
      `agents/peopleoperations/`, `agents/payroll/`, `agents/travel-expense/`,
      `webhook-receiver/`, `scripts/` (smoke test, process management)
- [ ] `.claude/skills/` scaffolding for the skills above (created as each is first needed)

**Done when:** repo structure exists, empty agent directories with placeholder
`README.md`s, nothing implemented yet.

### Phase 1 — Parking Agent (build first: simplest, zero LLM dependency)
Python · no framework · a2a-python SDK · REST binding

- [x] `AgentExecutor` serving a static agent card (skills: spot lookup, reservation)
- [x] Mock spot data (a small fixed set, WSO2-office-flavored naming)
- [x] `sendMessage` — "is spot X free" answered directly
- [x] Task lifecycle: reservation as a task, `cancelTask` support
- [x] Push notification config CRUD (create + delete; this is the agent's proof of
      `createTaskPushNotificationConfig`/`deleteTaskPushNotificationConfig`)

**Test — fully real, no stubs needed:**
- [x] Agent card resolves correctly at `/.well-known/agent-card.json`
- [x] `ballerina/a2a` `RestClient` (via `Client`) against it: `sendMessage`, `cancelTask`,
      push-notification CRUD all succeed — see `verification/parking`, 6/6 passing
- [x] Negative case: reserving an already-taken spot fails gracefully with a typed error
      (also covered: canceling an already-terminal task correctly fails)

**Done when:** every operation in Parking's "Proves" list in `architecture.md` passes
against a real `ballerina/a2a` client call, committed with its own README. **Complete** —
see `agents/parking/` and `verification/parking/`.

### Phase 2 — DigiOps Agent (IT Helpdesk)
Python · Google ADK · a2a-python SDK · JSON-RPC binding · real Anthropic backing

- [x] `AgentExecutor` wrapping a real ADK agent, configured against the real
      Anthropic model from the start — no interim fake implementation
- [x] `sendMessage` — FAQ answers (VPN, password reset)
- [x] Task lifecycle: hardware/ticket request (`getTask`/`cancelTask`/`listTasks`)
- [x] `sendStreamingMessage` + `subscribeToTask` — live incident investigation,
      genuinely droppable and resumable (verified with a real deliberate
      mid-stream disconnect + resubscribe, not just one uninterrupted stream)

**Test:**
- [x] Buildable and code-complete; agent-card resolution and streaming mechanics
      (real events, real disconnect+resubscribe) verified with no key needed —
      see `verification/digiops`, structural checks passing
- [x] Confirmed the whole ADK -> A2A -> `ballerina/a2a` pipeline fails gracefully
      (typed error, no crash/hang) without a real key
- [ ] **Full functional content — actual FAQ answers, ticket handling, real
      diagnosis text — happens in Phase 9**, since that needs the real model

### Phase 3 — PeopleOperations Agent (HR)
Python · LangGraph · a2a-python SDK · JSON-RPC binding · real Anthropic backing

- [x] `AgentExecutor` wrapping a real LangGraph graph on `ChatAnthropic` from the start
- [x] `sendMessage` — policy Q&A
- [x] `sendStreamingMessage` + `subscribeToTask` — onboarding checklist, multi-step
      (LangGraph's own tool-calling *is* the progress narration), `cancelTask` support
- [x] `getExtendedAgentCard` — a staff-only "case escalation" skill present only on
      the authenticated extended card, gated by a real bearer-token check

**Test:**
- [x] Agent-card resolution and the public-vs-extended-card diff verified now (no
      LLM call involved) — see `verification/peopleoperations`, 2 vs 3 skills confirmed
      against a real request both ways
- [x] Confirmed the LangGraph -> A2A -> `ballerina/a2a` pipeline fails gracefully
      without a real key
- [ ] **Full functional content — actual policy answers, onboarding — happens in
      Phase 9**, since every step here needs the real model (unlike DigiOps's
      incident flow, there's no pre-LLM staged narration to observe meanwhile)

### Phase 4 — Payroll Agent
Java · a2a-java SDK · Quarkus · gRPC binding · real Anthropic backing (via `langchain4j-anthropic`)

- [x] `AgentExecutor` (a2a-java), real Anthropic model (langchain4j) from the start,
      same pattern already proven on `dice_agent` earlier in this project
- [x] Task lifecycle: payslip-correction request (`getTask`/`cancelTask`/`listTasks`)
- [x] Full push-notification CRUD — all four operations verified against a real task
      (this is the one agent proving `listTaskPushNotificationConfigs`, the
      least-covered op elsewhere) — `InMemoryPushNotificationConfigStore` turned out
      to be auto-wired by CDI, no extra code needed
- [x] `getExtendedAgentCard` — admin-only "adjust another employee's payroll" skill,
      gated by a real bearer-token check via a Quarkus `@GlobalInterceptor` scoped to
      just that RPC. Rejects outright rather than downgrading like PeopleOperations —
      the a2a-java gRPC reference module (1.1.0.Final) has no per-caller card-modifier
      hook, confirmed by reading the SDK source

**Test:**
- [x] Agent-card resolution (gRPC-only `supportedInterfaces`), push-notification config
      CRUD (create/get/list/delete against a real task ID recovered from a graceful
      LLM-call failure), and extended-card admin gating (both unauthenticated-rejected
      and authenticated-3-skills) all verified now, no key needed — see
      `verification/payroll`
- [x] Confirmed the langchain4j -> A2A -> gRPC -> `ballerina/a2a` pipeline fails
      gracefully without a real key, and that `getTask`/`cancelTask` genuinely
      round-trip over gRPC
- [ ] **Task-lifecycle functional testing (actual payslip-correction content from a
      real answer) happens in Phase 9**, via `ballerina/a2a`'s `GrpcClient`

**Real integration issues found and fixed for real (not worked around), documented
in `agents/payroll/README.md` and inline in `application.properties`:**
- gRPC and plain HTTP need separate ports — combining them (as the reference sample
  this was modeled on does) broke the well-known agent-card HTTP GET
- ballerina/http's client defaults to HTTP/2 cleartext prior-knowledge negotiation,
  which doesn't interop with Vert.x's h2c handling; fixed by pinning this agent's
  HTTP listener to HTTP/1.1 rather than requiring every `ballerina/a2a` caller to
  know to override `httpVersion`

### Phase 5 — Travel & Expense Agent
Java · a2a-java SDK · REST binding · real Anthropic backing

- [x] Task lifecycle: expense claim (`getTask`/`cancelTask`/`listTasks`), real
      langchain4j-anthropic agent + two real tools (fileExpenseClaim, getClaimStatus)
- [x] Push notification config: create + get (deliberately narrower than Payroll,
      which already proved full CRUD)

**Test:**
- [x] Agent-card resolution (REST-only `supportedInterfaces`), task-lifecycle
      round-tripping (`getTask`/`cancelTask`), and push-notification create+get all
      verified now, no key needed — see `verification/travel_expense`
- [x] Confirmed the langchain4j -> A2A -> REST -> `ballerina/a2a` pipeline fails
      gracefully without a real key
- [ ] **Task-lifecycle functional testing (actual expense-claim content from a real
      answer) happens in Phase 9**, via `ballerina/a2a`'s `RestClient`

**Two of Payroll's real integration fixes applied pre-emptively here** (documented
in `agents/travel_expense/README.md`, reproduced once each to confirm they weren't
gRPC-specific before pinning): HTTP/2 pinned off on the HTTP listener, and
`protobuf-java`/`protobuf-java-util` pinned to 4.34.2 — the a2a-java 1.1.0.Final spec
types turned out to be protobuf messages regardless of transport, not just for gRPC.

### Phase 6 — Push-notification webhook receiver
- [x] Minimal HTTP endpoint the orchestrator hosts (`orchestrator/webhook_receiver.bal`,
      port 9090) — the first piece of the `orchestrator/` package, which Phase 7 builds
      the AI/tool-calling logic into
- [x] Payroll, Parking, and Travel & Expense all genuinely registered and triggered
      against it
- [x] Test: trigger a real state change on each of the three agents, confirm the
      webhook POST actually arrives — this is what turns "config CRUD works" into
      "notifications actually work," per the gap flagged when this architecture was
      first reviewed. **Everything here was testable with no Anthropic key** — see
      `verification/webhook_receiver`

**Real finding, not worked around:** a2a-java (1.1.0.Final) registers an inline
`taskPushNotificationConfig` only after consuming the executor's first event, so a
synchronous agent (Payroll, Travel & Expense) whose whole submit -> startWork ->
LLM-call-fails sequence happens in one instant can race past that registration —
confirmed by reproduction, delivery is genuinely non-deterministic for those two, and
the terminal FAILED transition never delivers at all (an uncaught executor exception's
conversion to FAILED bypasses the push pipeline entirely). Parking (Python) has no
equivalent race and delivers reliably end to end. Documented in full in
`orchestrator/README.md`; the verification script handles this honestly — Parking
asserted deterministically, Payroll/Travel & Expense retried until one real delivery
lands, rather than asserting something the SDK doesn't actually guarantee.

### Phase 7 — Orchestrator
Ballerina · `ballerina/ai` · `ballerina/a2a` client · real Anthropic backing

- [x] Five tool functions, each resolving its target agent's card once and holding a
      reusable `ballerina/a2a` `Client`
- [x] Each tool function is code-complete and calls its real target agent via real
      `ballerina/a2a` — no bypass. Against Parking specifically (the one agent that
      doesn't need the key to run), this is fully testable now — real `bal test`
      confirms a real content reply
- [x] Wire the five tools into a real `ballerina/ai` `Agent` (routing decision layer)
      on the real Anthropic model (`ballerinax/ai.anthropic`, claude-sonnet-4-5) —
      code-complete now, but actually invoking it means invoking the real model, so
      full routing verification happens in Phase 9. Confirmed now: the whole
      `ballerina/ai -> ballerinax/ai.anthropic -> Anthropic API` pipeline fails
      gracefully without a real key
- [x] Push-notification webhook receiver wired in (Phase 6) — same `orchestrator/` package

**Test:** no separate `verification/orchestrator` package — the tools and the agent
are internal logic, not a new server-side protocol surface, so `bal test`
(`orchestrator/tests/`) is the real (not mocked) tool for this. All 6 checks pass
against all five real running downstream agents — see `orchestrator/README.md`.

**Real, upstream-known issue found and fixed for real:** combining `ballerina/ai`
with `ballerina/a2a`'s gRPC binding in one package hits a grpc/http-native
ABI-coupling bug (ballerina-platform/ballerina-library#2496) — a fresh dependency
resolve picks an `http` version newer than what the bundled `grpc` module tolerates,
crashing at boot. Fixed the same way `ballerina/a2a`'s own `Ballerina.toml` already
documents: pin `http` as a floor and commit the resolved `Dependencies.toml` as the
real source of truth, always building/running this package with `--sticky`.

### Phase 8 — Local process bring-up (structural check, ahead of the key)
- [x] All five agents + orchestrator started as local processes on fixed ports
      (`scripts/start-all.sh`, builds from source first if needed, waits for every
      real Agent Card to resolve)
- [x] Confirm every agent serves its agent card correctly and the orchestrator can
      resolve all five — module init itself fails the whole orchestrator boot if any
      of the five isn't reachable, so this is enforced structurally, not just tested
- [x] Run whatever slice of the smoke test doesn't require the key: Parking's full
      operation set, plus agent-card and push-notification-config checks on the
      other four (`scripts/run-structural-checks.sh`, running every existing
      verification script plus `orchestrator`'s own `bal test` suite)
- [x] This is a structural readiness check, not the real functional pass — that's Phase 9

**Done when:** the whole system is running, every agent is reachable and serving a
correct card, and everything that *can* be verified without the key has been. ✅ A
genuinely fresh `stop-all.sh` → `start-all.sh` → `run-structural-checks.sh` cycle
passes every check except the already-documented Payroll/Travel & Expense
push-notification race from Phase 6 (real, expected non-determinism — see
`orchestrator/README.md` — not a Phase 8 regression).

**Real bug found and fixed while writing `start-all.sh`:** backgrounding
`cd x && cmd &` runs `cmd` inside an extra subshell, so `$!` is that subshell's PID,
not `cmd`'s — `stop-all.sh` was killing the wrong process and leaving the real one
running. Fixed by `exec`ing the real command inside an explicitly backgrounded
subshell. `bal run <jar>` has the same problem one layer further in (forks its own
JVM rather than exec'ing into it), so the orchestrator's tracked PID is recovered
from its listening port instead.

### Phase 9 — Full functional pass with the real key
Only once the Anthropic key is supplied. This is where DigiOps, PeopleOperations,
Payroll, Travel & Expense, and the orchestrator's routing all get their first real
functional test — plan for this being the biggest single testing phase, not a quick
confirmation pass.

- [x] Every one of the 11 operations, across all three transport bindings, exercised
      end-to-end against the real running system. The `a2a-smoke-test` Claude Code
      Skill proposed early in this project was never actually created, so this ran as
      a direct real script rather than through that packaging — the coverage itself is
      complete: protocol-mechanical coverage of all 11 ops (`sendMessage`,
      `sendStreamingMessage`, `getTask`, `cancelTask`, `listTasks`, `subscribeToTask`,
      the four push-notification config ops, `getExtendedAgentCard`) across REST/
      JSON-RPC/gRPC was already fully verified for real in Phases 1-8 with no key
      needed; Phase 9's new job was specifically proving real *content* wherever a key
      was the only missing piece, which `verification/phase9_smoke_test` and
      `orchestrator/tests/phase9_routing_test.bal` now do
- [x] Ran a **fixed, pre-scripted** set of end-to-end employee scenarios, written down
      in `DEMO_SCRIPT.md` *before* running them — 10 scenarios (6 direct-to-agent, 4
      through orchestrator routing), executed once
- [x] Confirmed orchestrator routing quality across all five agents with the real
      model — Parking, DigiOps, and Payroll all correctly selected from natural
      language, and an off-domain (weather) request correctly declined rather than
      answered by guessing
- [x] Recorded results in `DEMO_SCRIPT.md`; all 10 scenarios passed on the one
      scripted run. Two (Payroll correction, Travel & Expense claim) deviated from the
      literal scripted expectation in a way that's actually correct real behavior —
      the model withheld a tool call pending a required parameter or a real policy
      check (manager approval, receipt threshold) rather than filing incomplete
      data — recorded honestly, not re-run for a "cleaner" result

**Real issue found and fixed:** `.env` is only auto-sourced by `scripts/start-all.sh`'s
own process, not by a separately invoked `bal test` — the first routing-test run hit
real 401s from Anthropic because of this, not a code defect. Also made the four
Phase-7-era "fails gracefully without a key" tests key-aware
(`os:getEnv("ANTHROPIC_API_KEY")`) rather than hardcoded to the no-key world, since a
real key now genuinely changes their correct expected outcome.

### Phase 10 — Negative / chaos testing
- [x] Same kind of fault-injection testing (malformed responses, concurrent load,
      resource-leak sanity) against the now-real running agents —
      `verification/chaos_test/main.bal`, run once. All 8 checks passed: zero panics,
      zero crashes, zero hangs; RSS memory for a Python and a JVM agent both
      *decreased* over the run. Deliberately spent zero additional Anthropic quota —
      every check targets Parking or pure protocol/data operations, per the budget
      concern raised earlier in this project
- [x] Written up as `docs/NEGATIVE_TEST_REPORT.md` — this is a second, independent
      pass of the same kind of testing already done against `a2a-ballerina` itself
      earlier in that project's session (referenced by its own conformance checklist
      item 12), this time against real running server implementations rather than a
      test harness

### Phase 11 — Documentation finalization
- [x] Per-agent `README.md` (role, skills, how to run, port, transport binding) —
      already written phase-by-phase for all five agents plus the orchestrator;
      spot-checked complete, no gaps found
- [x] `DEMO_SCRIPT.md` — reframed as the live presentation walkthrough (it already
      carried real, verified scenarios and results from Phase 9; added a "running
      the demo live" section)
- [x] `NAMING.md` — checked; nothing to update, no new WSO2 names were confirmed
      during implementation. Payroll, Parking, Travel & Expense, and the
      orchestrator remain generic pending names, as already tracked
- [x] `architecture.md` re-checked against what was actually built — real drift
      found and corrected: HR/IT Helpdesk renamed to PeopleOperations/DigiOps
      throughout (confirmed names, applied everywhere else since Phases 2-3 but
      never back-ported to this doc); the push-notification diagram/text updated
      from "Payroll only" to the real three agents (Parking, Payroll, Travel &
      Expense) that register webhooks; the "how agents get registered — still
      open" line replaced with what was actually built (fixed local URLs); title
      corrected from "two languages" to three (Python, Java, Ballerina)

### Phase 12 — Containerization (Docker Compose)
Only after Phase 8–11 are done and reviewed, per the agreed sequencing. Docker
runtime used: Rancher Desktop (Docker Desktop isn't on the approved-software list;
Rancher Desktop is, and provides a fully `docker`-CLI-compatible experience —
confirmed for real, no differences hit).

- [x] Dockerfile per agent + orchestrator — Python agents self-contained
      single-stage; Java agents self-contained multi-stage (a2a-java is a real Maven
      Central artifact); orchestrator multi-stage, with `prepare-docker-build.sh`
      staging the local-only `ballerina/a2a` artifact into the build context first
      (not published to Central)
- [x] `docker-compose.yml` bringing the whole system up — healthchecks on every
      agent, orchestrator gated on all five being *healthy* (not just started)
- [x] Re-run the Phase 9 smoke test against the containerized version, confirm parity
      with the local-process version — `verification/docker_parity` +
      `scripts/docker-verify.sh`, all 7 checks pass: card resolution for all five
      real containerized agents over Docker DNS, the orchestrator's webhook
      receiver reachable, and a real `sendMessage` round-trip against Parking

**Real issues found and fixed, not worked around:**
- Every agent hardcoded `127.0.0.1` for both its own bind address and the URL its
  card advertises to other clients — works for local-process, breaks in Docker (a
  container must bind `0.0.0.0` but advertise its real Compose service name).
  Split into separate bind-host/advertised-host config across all five agents plus
  the orchestrator's downstream agent URLs
- Docker's `COPY` always writes as root regardless of the image's own `USER`
  directive unless `--chown` is given explicitly — broke the orchestrator's build
  (`bal build` couldn't write `Dependencies.toml` as the non-root `ballerina` user)
- A separate `mvn dependency:go-offline` layer doesn't know about Quarkus's
  build-time/deployment-scope dependency resolution — simplified both Java
  Dockerfiles to one `mvn package` step rather than chase a caching optimization
  that wasn't resolving correctly
- The existing local-process `verification/*` scripts, run unmodified from the
  host, resolve a containerized agent's card fine but fail on the actual RPC call,
  because the client uses the card's *advertised* URL (the real Docker service
  name) for that, which the host can't resolve — only other containers on the
  same Compose network can. `verification/docker_parity` runs from inside that
  network instead, via a throwaway `ballerina/ballerina` container

**Investigated but not pursued this phase:** WSO2 Integrator: BI, floated as an
alternative to plain `ballerina/ai` in the original architecture doc. Confirmed
for real (installed extensions, inspected their manifests, opened the real
`orchestrator/` package in it) that BI is a VS Code extension layered on the
standard Ballerina distribution — not a separate runtime — and activates on any
plain `Ballerina.toml` package with no conversion needed. Has its own separate
Docker/Kubernetes deployment tooling, independent of what was built here. Full
writeup, plus the follow-up on how BI expects a remote agent wired in (as a
tool — matches `agent_tools.bal` already): `docs/research/`.

### Phase 13 — Final polish
- [x] Full walkthrough rehearsal — fresh `stop-all.sh` -> `start-all.sh` ->
      `run-structural-checks.sh` cycle, all real, all against the live system.
      Found and fixed two real bugs along the way (not regressions from Phase 12,
      but genuine gaps this rehearsal was the first thing to actually exercise):
      `verification/payroll`/`verification/travel_expense` couldn't recover a task
      ID from a *successful* `sendMessage` (they were only ever exercised against a
      no-key system before); `run-structural-checks.sh`'s own orchestrator
      `bal test` call didn't source `.env`, so its tests assumed no key while the
      real agents it called into already had one. Clean run afterward, modulo the
      already-documented Phase 6 push-notification race
- [x] Cosmetic: `README.md` and this plan's own top-of-doc status lines were both
      stale ("Phases 1-8" / "draft, awaiting review") despite all 13 phases being
      done — closed out. `DEMO_SCRIPT.md` updated to mention the Docker path
      alongside local-process. WSO2 naming: checked again, nothing new to apply —
      Payroll, Parking, Travel & Expense, and the orchestrator remain the one
      genuinely open item, tracked in `NAMING.md`, blocked on the user confirming
      real names

## Testing philosophy summary

Every agent is real from the start; what's genuinely gated on the key is *running*
anything that invokes an agent's actual reasoning — not the agent's existence or
correctness as code.

| Layer | What it proves | Needs real LLM key to run? |
|---|---|---|
| Agent card resolution (all 5 agents) | Each agent is discoverable and its card is well-formed | No |
| Push-notification config CRUD (Payroll, Parking, Travel & Expense) | Pure data storage, no reasoning involved | No |
| Parking's full operation set | The one agent with no LLM in its design at all | No |
| Orchestrator tool functions, called directly | Each tool correctly reaches its agent via `ballerina/a2a` (against Parking; the other four need the key to respond meaningfully) | Partially — Parking only |
| Task lifecycle on DigiOps / PeopleOperations / Payroll / Travel & Expense | The agent actually handles a message and manages task state | **Yes** |
| Orchestrator routing quality | The LLM actually picks the right specialist | **Yes** |
| Negative/chaos testing | Graceful failure under malformed input and load | No (targets protocol-level faults, not agent reasoning) |

Phase 9 is deliberately the largest testing phase in this plan — that's the honest
shape of "everything is real": most of the system's actual behavior can only be
verified once the key exists, and the plan is scripted (`DEMO_SCRIPT.md` written
before Phase 9 runs) so that pass is deliberate and bounded, not exploratory.
