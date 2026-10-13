#!/usr/bin/env bash
# Brings up the whole Employee Concierge system as real local processes:
# all five agents (scripts/start-agents.sh), then the orchestrator (which
# requires all five already reachable — it resolves every real Agent Card
# at module init). Each process's real stdout/stderr goes to
# logs/<name>.log; PIDs are tracked in .pids/ so stop-all.sh can shut
# everything down cleanly.
#
# Use scripts/start-agents.sh instead if you want to run or chat with the
# orchestrator through WSO2 Integrator: BI rather than via this script —
# see orchestrator/README.md's "Run it" section.
#
# ANTHROPIC_API_KEY comes from a git-ignored .env at the repo root (never
# passed on the command line or exported by hand) and is passed through
# to the orchestrator for real LLM answers (Phase 9); start-agents.sh
# sources the same .env for the five agents' own copy of the key.
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

"$ROOT_DIR/scripts/start-agents.sh"

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

unset JAVA_HOME
if [ ! -f "$ROOT_DIR/orchestrator/target/bin/orchestrator.jar" ]; then
    echo "building orchestrator (bal build --sticky)..."
    (cd "$ROOT_DIR/orchestrator" && bal build --sticky)
fi
echo "starting orchestrator..."
( cd "$ROOT_DIR/orchestrator" && exec env ${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"} \
    nohup bal run target/bin/orchestrator.jar \
    > "$LOG_DIR/orchestrator.log" 2>&1 ) &
wait_for orchestrator "http://127.0.0.1:9090/webhooks/received"
# `bal run <jar>` forks its own JVM rather than exec'ing into it, so $!
# above is bal's launcher PID, not the real one listening on 9090 — find
# the actual listener now that wait_for has confirmed it's up.
lsof -i :9090 -sTCP:LISTEN -t | head -1 > "$PID_DIR/orchestrator.pid"

echo
echo "=== all six processes up ==="
echo "Parking:            http://127.0.0.1:8000"
echo "DigiOps:             http://127.0.0.1:8001"
echo "PeopleOperations:    http://127.0.0.1:8002"
echo "Payroll:             http://127.0.0.1:8003 (grpc: 9003)"
echo "Travel & Expense:    http://127.0.0.1:8004"
echo "Orchestrator:        http://127.0.0.1:9090 (webhook receiver), http://127.0.0.1:8090 (chat)"
echo
echo "Run scripts/run-structural-checks.sh next, or scripts/stop-all.sh when done."
