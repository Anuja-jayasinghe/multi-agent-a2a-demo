#!/usr/bin/env bash
# Brings up just the five downstream agents (Parking, DigiOps,
# PeopleOperations, Payroll, Travel & Expense) as real local processes,
# without the orchestrator. Use this before running or chatting with the
# orchestrator through WSO2 Integrator: BI (or a bare `bal run`) instead
# of scripts/start-all.sh — the orchestrator resolves all five real Agent
# Cards at module init, so it fails with a connection error if it boots
# before these five are reachable, no matter what starts it. See
# orchestrator/README.md's "Run it" section.
#
# scripts/start-all.sh calls this script for the same five agents, then
# starts the orchestrator itself too — use that instead if you don't need
# BI in the loop.
#
# ANTHROPIC_API_KEY comes from a git-ignored .env at the repo root (never
# passed on the command line or exported by hand). Without it, all five
# agents still boot and serve their cards correctly, but real requests
# fail gracefully.
#
# PAYROLL_ADMIN_TOKEN and PEOPLEOPS_STAFF_TOKEN come from .env, with no
# fallback if left unset. Without one, that agent's extended-card gating
# (Payroll's AdminOnlyExtendedCardInterceptor, PeopleOperations'
# BearerTokenContextBuilder) stays permanently closed -- neither has a
# hardcoded value to fall back to either, so there is no credential that
# will work until one is set. Everything else -- public skills, ordinary
# chat, the orchestrator's own routing -- is unaffected; only the
# extended-card demo needs a real value here.
#
# ONBOARDING_STEP_DELAY_SECONDS, OFFBOARDING_STEP_DELAY_SECONDS
# (peopleoperations) and HARDWARE_PROVISIONING_STEP_DELAY_SECONDS
# (digiops) default to ~200s each (3 steps ~= 10 real minutes) -- genuine
# long-running, cancellable tasks, not simulated ones. Each Python process
# reads its value once at start,
# so setting either in .env only takes effect on the *next* time this
# script starts that agent -- it does nothing for an already-running one,
# and setting it in a different shell (e.g. the one running `bal test`)
# has no effect at all.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
PID_DIR="$ROOT_DIR/.pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
fi

: "${PAYROLL_ADMIN_TOKEN:=}"
: "${PEOPLEOPS_STAFF_TOKEN:=}"
export PAYROLL_ADMIN_TOKEN PEOPLEOPS_STAFF_TOKEN

if [ -z "$PAYROLL_ADMIN_TOKEN" ] || [ -z "$PEOPLEOPS_STAFF_TOKEN" ]; then
    echo "Note: PAYROLL_ADMIN_TOKEN and/or PEOPLEOPS_STAFF_TOKEN is unset." >&2
    echo "That agent's extended-card auth gating will stay closed to every" >&2
    echo "caller -- set it in .env to test case-escalation or" >&2
    echo "adjust-other-employee-payroll. Nothing else is affected." >&2
    echo >&2
fi

wait_for() {
    local name="$1" url="$2" attempts=0
    until curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q '^200$'; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 30 ]; then
            echo "[FAIL] $name did not become ready at $url — see logs/$name.log"
            return 1
        fi
        sleep 1
    done
    echo "[ok] $name ready at $url"
}

start_python_agent() {
    local name="$1" dir="$2" port="$3"; shift 3
    local agent_dir="$ROOT_DIR/agents/$dir"
    if [ ! -d "$agent_dir/.venv" ]; then
        echo "building $name (uv sync)..."
        (cd "$agent_dir" && uv sync)
    fi
    echo "starting $name..."
    # A backgrounded `cd x && cmd &` runs cmd inside an extra subshell, so
    # $! there is that subshell's PID, not cmd's — stop-all.sh would then
    # kill the wrong process and leave the real one running. exec inside
    # an explicitly backgrounded subshell replaces the subshell's own
    # process image with the real command, so its PID *is* $!.
    ( cd "$agent_dir" && exec env "$@" nohup .venv/bin/python3 __main__.py \
        > "$LOG_DIR/$name.log" 2>&1 ) &
    echo $! > "$PID_DIR/$name.pid"
    wait_for "$name" "http://127.0.0.1:$port/.well-known/agent-card.json"
}

start_java_agent() {
    local name="$1" dir="$2" port="$3"; shift 3
    local agent_dir="$ROOT_DIR/agents/$dir"
    if [ ! -f "$agent_dir/target/quarkus-app/quarkus-run.jar" ]; then
        echo "building $name (mvn package)..."
        (cd "$agent_dir" && mvn -q -DskipTests -Dquarkus.analytics.disabled=true package)
    fi
    echo "starting $name..."
    ( cd "$agent_dir" && exec env "$@" nohup java -jar target/quarkus-app/quarkus-run.jar \
        > "$LOG_DIR/$name.log" 2>&1 ) &
    echo $! > "$PID_DIR/$name.pid"
    wait_for "$name" "http://127.0.0.1:$port/.well-known/agent-card.json"
}

start_python_agent parking parking 8000
start_python_agent digiops digiops 8001 ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"}
start_python_agent peopleoperations peopleoperations 8002 ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"}
start_java_agent payroll payroll 8003 PAYROLL_ADMIN_TOKEN="$PAYROLL_ADMIN_TOKEN" ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"}
start_java_agent travel_expense travel_expense 8004 ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"}

echo
echo "=== all five downstream agents up ==="
echo "Parking:            http://127.0.0.1:8000"
echo "DigiOps:             http://127.0.0.1:8001"
echo "PeopleOperations:    http://127.0.0.1:8002"
echo "Payroll:             http://127.0.0.1:8003 (grpc: 9003)"
echo "Travel & Expense:    http://127.0.0.1:8004"
echo
echo "Now open orchestrator/ in WSO2 Integrator: BI and Run/Debug or chat"
echo "with it directly — or run scripts/start-all.sh instead if you don't"
echo "need BI in the loop."
