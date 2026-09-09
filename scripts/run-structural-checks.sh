#!/usr/bin/env bash
# Runs every real ballerina/a2a verification script — Parking's full
# operation set, agent-card and push-notification-config checks on the
# other four, and the orchestrator's own bal test suite — against a
# system already brought up by start-all.sh. Real network calls against
# real running processes throughout; nothing here is mocked.
#
# Every check here is genuinely correct whether or not .env holds a real
# ANTHROPIC_API_KEY: with no key, the LLM-backed checks assert graceful
# failure; with a real key (the default local dev setup since Phase 9),
# they assert real, non-empty content instead — so this now spends a
# small, bounded amount of real Anthropic quota per run once a key is
# configured (a handful of short calls, not something that scales with
# how often this script is run in a loop).
#
# Run this against a FRESHLY STARTED stack. The parking checks reserve
# real spots (A04, B01), and the agents hold reservations in memory
# (agents/parking/data.py seeds A02/B02 as taken at import and never
# resets), so a second run against the same processes finds A04 already
# booked and fails the "resolves naturally -> COMPLETED" check. That is
# the state left over from the previous run, not a regression --
# re-run start-all.sh before re-running this.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset JAVA_HOME

# Source .env the same way start-all.sh does, so this script's own
# orchestrator `bal test` step sees the same ANTHROPIC_API_KEY the
# already-running agents booted with — otherwise the orchestrator's tests
# assume no key (and expect a graceful error) while the real agents
# they're calling already have one and answer for real, a false failure
# found for real while rehearsing the whole system in Phase 13.
if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
fi

failures=0
run_check() {
    local name="$1" dir="$2"
    echo "=== $name ==="
    ( cd "$ROOT_DIR/$dir" && rm -f Dependencies.toml && bal run --sticky )
    if [ $? -ne 0 ]; then
        echo "[FAIL] $name"
        failures=$((failures + 1))
    fi
    echo
}

run_check "Parking" "verification/parking"
run_check "DigiOps" "verification/digiops"
run_check "PeopleOperations" "verification/peopleoperations"
run_check "Payroll" "verification/payroll"
run_check "Travel & Expense" "verification/travel_expense"
run_check "Push-notification webhook receiver" "verification/webhook_receiver"

echo "=== Orchestrator (bal test) ==="
# bal test loads the whole orchestrator module, including its own
# webhook_receiver.bal service declaration — that collides on port 9090
# with the real orchestrator process start-all.sh already has running.
# Stop it first, run the tests, then bring it back so the system is left
# fully up the same way start-all.sh left it.
orchestrator_pid_file="$ROOT_DIR/.pids/orchestrator.pid"
orchestrator_was_running=false
if [ -f "$orchestrator_pid_file" ] && kill -0 "$(cat "$orchestrator_pid_file")" 2>/dev/null; then
    orchestrator_was_running=true
    echo "stopping the running orchestrator for the duration of its own test suite..."
    kill "$(cat "$orchestrator_pid_file")" 2>/dev/null
    sleep 2
fi

( cd "$ROOT_DIR/orchestrator" && bal test --sticky )
if [ $? -ne 0 ]; then
    echo "[FAIL] Orchestrator"
    failures=$((failures + 1))
fi

if [ "$orchestrator_was_running" = true ]; then
    echo "restarting the orchestrator..."
    ( cd "$ROOT_DIR/orchestrator" && exec nohup bal run target/bin/orchestrator.jar \
        > "$ROOT_DIR/logs/orchestrator.log" 2>&1 ) &
    for _ in $(seq 1 30); do
        curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9090/webhooks/received 2>/dev/null | grep -q '^200$' && break
        sleep 1
    done
    lsof -i :9090 -sTCP:LISTEN -t | head -1 > "$orchestrator_pid_file"
    echo "[ok] orchestrator back up"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "=== ALL STRUCTURAL CHECKS PASSED ACROSS THE WHOLE SYSTEM ==="
else
    echo "=== $failures CHECK GROUP(S) FAILED ==="
    exit 1
fi
