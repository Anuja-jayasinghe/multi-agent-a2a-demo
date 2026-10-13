# Full round check: `ballerina/a2a` client + this demo

**Date:** 2026-08-25
**Scope:** Real, live verification across both repos — `a2a-ballerina` (the
client library) and this demo (orchestrator + all 5 agents) — after the
Phase 13 Part 3 capability expansion and the `a2a-ballerina` license-header
work. No mocks: every check below ran against real, live processes with a
real Anthropic key.

## Method

1. `bal build` + `bal test --sticky` in `a2a-ballerina/ballerina` directly.
2. Compared the orchestrator's locally-published `ballerina/a2a` package
   (`repository = "local"` in `Ballerina.toml`, resolved from
   `~/.ballerina/repositories/local`) against `a2a-ballerina`'s current
   `main` branch source.
3. Started all 5 real downstream agents (`scripts/start-agents.sh`) and ran
   the orchestrator's full `bal test --sticky` suite twice — once with
   shortened staged-wait env vars (to separate real bugs from "this test
   assumes ~200s delays" timing artifacts), once with real default delays
   for an authoritative final result.

## Finding 1 (fixed): locally-published `ballerina/a2a` was stale

The orchestrator and every `verification/*` script depend on `ballerina/a2a`
via `repository = "local"`, which resolves from a `bal pack && bal push
--repository=local` snapshot, not live source. That snapshot was last
published **2026-08-20** — before the REST content-type fix (`b6bc29e`,
PR #41 in `a2a-ballerina`) and the per-file license-header work (PR #44).

Confirmed directly: the locally-published `rest_client.bal` still sent
`Content-Type: application/json` (the pre-fix, spec-incorrect value), while
`a2a-ballerina`'s real `main` branch had `application/a2a+json` since
2026-08-25.

**Fixed**: re-ran `bal pack && bal push --repository=local` from
`a2a-ballerina/ballerina`. Confirmed the republished package now carries the
current source. Rebuilt the orchestrator (`bal build --sticky`) against it
— clean.

**Process gap, not a one-time fix**: nothing re-publishes this automatically.
Any `a2a-ballerina` change requires a manual republish before this demo
picks it up — already documented in `agents/travel_expense/README.md` and
`orchestrator/prepare-docker-build.sh`, but easy to forget (this is exactly
what happened here). Worth a `scripts/` helper if this keeps recurring.

## Finding 2 (resolved — see update below): the REST content-type fix breaks real interop with the actual `a2a-java` reference server

Republishing the fixed client (Finding 1) surfaced a real regression:
`testDelegateToTravelExpense` failed with `"expected a real, non-empty reply
with a real key"` — TravelExpense (the one demo agent on the REST binding)
stopped answering entirely.

Reproduced directly against the live TravelExpense agent:

```
$ curl -X POST http://127.0.0.1:8004/v1/message:send \
    -H "Content-Type: application/a2a+json" -d '...'
HTTP 415
{"error":{"code":415,"status":"INVALID_ARGUMENT","message":"Incompatible content types", ...}}
```

Confirmed the root cause by decompiling the real, currently-used SDK jar
(`a2a-java-sdk-reference-rest-1.1.0.Final.jar`,
`org/a2aproject/sdk/server/rest/quarkus/A2AServerRoutes.class`): its Vert.x
route registration hardcodes `.consumes("application/json")`. The string
`a2a+json` does not appear anywhere in that jar. This is the actual,
currently-released reference REST server implementation TravelExpense's
`pom.xml` depends on (`a2a-java-sdk-reference-rest`) — not a
misconfiguration on our end.

So: `application/a2a+json` is what the real A2A v1.0.0 spec text requires
(verified directly against the spec in an earlier session — see
`a2a-ballerina/CONFORMANCE_CHECKLIST.md`'s Step 1 entry), but it is **not**
what the actual, currently-released Java reference server accepts. The spec
and its own reference implementation disagree, and `a2a-ballerina`'s client
currently sides with the spec text over real-world interop with the one
concrete server implementation this demo depends on.

**Not resolved here** — this reverses a previously-reviewed, explicitly
spec-verified fix in `a2a-ballerina` (PR #41), so it needs a real decision,
not a unilateral revert:

- Revert `rest_client.bal` to `application/json` by default (real interop
  with the actual `a2a-java-sdk-reference-rest` today; not spec-conformant
  per the letter of v1.0.0), or
- Keep `application/a2a+json` and treat this as a known, tracked
  incompatibility with `a2a-java-sdk-reference-rest:1.1.0.Final`
  specifically (spec-conformant; breaks real interop with this one real
  server until it updates), or
- Make the REST binding negotiate (send `application/a2a+json`, fall back to
  `application/json` on a `415`) — more real-world-robust, more code.

**Update (a2a-ballerina PR #45):** implemented the third option. `RestClient`
sends `application/a2a+json` by default and transparently retries once with
`application/json` on a real `415`, then remembers the choice per client
instance so every later call skips straight to it. Verified against the
real, live TravelExpense agent: a request that previously failed outright
now succeeds transparently. 3 new tests in `rest_client_test.bal` exercise
the negotiation directly. `testDelegateToTravelExpense` now passes.

## Finding 3 (fixed): orchestrator test suite had a real test-currency gap from PR #35

`testHardwareProvisioningStartsAsBackgroundTask` and
`testCancelHardwareProvisioningMidFlight` both requested a **"docking
station"** — one of the four items PR #35 (DigiOps catalog-vs-approval
split) deliberately made resolve *fast*, skipping the staged
manager-approval wait entirely. Neither test was updated when that behavior
change shipped, so both started asserting the opposite of what the agent now
correctly does.

**Fixed**: both tests now request a "standing desk converter" (a real
over-catalog item, matching the item already used in PR #35's own live
verification), which genuinely exercises the staged path they're meant to
test. Added `testDigiOpsStandardCatalogRequestResolvesFast` alongside them
so the fast path PR #35 introduced has its own real coverage, matching how
`testParkingReservationTaskCompletes` already covers Parking's fast-settling
case.

## Finding 4 (mitigated): one pre-existing flaky test

`testParkingReservationTaskCompletes` passed twice, then failed once across
three runs — not from anything touched this round. Its employee-name
fixture is `"Task Lifecycle Test " + uuid:createType4AsString()`; on the
failing run, the LLM (correctly, per its own prompt instruction to never
invent/assume a name) judged that string as "doesn't look like an actual
person's name" and asked for clarification instead of proceeding. Same
category of LLM name-plausibility judgment call already documented for
DigiOps during PR #35's own live testing — inherent non-determinism on a
synthetic test fixture, not a code defect. **Update (demo PR #40):** replaced all 6 UUID-suffixed employee-name
fixtures across `agent_tools_test.bal` with a shared
`uniqueTestEmployeeName()` — a realistic name plus a short unique tag,
matching the flavor already used in Parking/DigiOps' own
live-verification fixtures. Reduces, not guarantees away, the odds of this
specific LLM judgment call; genuine non-determinism on a live model isn't
fully eliminable by fixture wording alone.

## Final state

- `a2a-ballerina`: `bal build` clean, `bal test --sticky` 441/441 + 3/3
  passing (3 new tests added by PR #45's content-type negotiation fix).
- Orchestrator, all 5 real agents live, real key, real default delays:
  23 tests, 23 passing. Both Finding 2 and Finding 4 addressed — see the
  update notes above.
