#!/usr/bin/env bash
# Opens one Terminal.app window per downstream agent -- and deliberately
# NOT the orchestrator, so you can run that from WSO2 Integrator: BI (Run,
# Debug, or its chat panel) against these five.
#
# This is the BI-shaped counterpart to watch-agents-local.sh, which starts
# six windows including the orchestrator. Running that one and then hitting
# Run in BI gives you 'failed to start server connector 0.0.0.0:8090:
# Address already in use', because the orchestrator is already up in a
# Terminal window -- BI is trying to start a second one. Use this script
# instead when BI owns the orchestrator.
#
# Each window runs its real process in the *foreground*, so the window IS
# that agent's live log: you watch it receive a task, work on it, and send
# the response back, in real time. Nothing is backgrounded or redirected.
#
# macOS + Terminal.app only. Ctrl-C in a window stops that one agent;
# closing the window does the same. No PID tracking, unlike
# start-all.sh/stop-all.sh -- each process lives in its own foreground
# window on purpose.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT_DIR/.watch-agents"

# Preflight. Starting an agent whose port is already taken fails several
# seconds later, inside a new window that may scroll away or be closed
# before it is read -- so the port is checked here, where the message is
# actually seen. This is the same class of failure the orchestrator hits
# on 8090, just caught before it happens rather than after.
PORTS_IN_USE=""
for port in 8000 8001 8002 8003 8004 9003; do
    if lsof -ti:"$port" >/dev/null 2>&1; then
        PORTS_IN_USE="$PORTS_IN_USE $port"
    fi
done
if [ -n "$PORTS_IN_USE" ]; then
    echo "Refusing to start: these agent ports are already in use:$PORTS_IN_USE" >&2
    echo >&2
    echo "Something is already running -- most likely a previous" >&2
    echo "watch-agents-local.sh / watch-agents-for-bi.sh / start-agents.sh." >&2
    echo "Close those Terminal windows, or run scripts/stop-all.sh, then retry." >&2
    exit 1
fi

# Not fatal: BI has not been told to run yet, so 8090 being busy now just
# means the orchestrator is already up somewhere and BI's Run would
# collide. Worth saying plainly, since that is the exact problem this
# script exists to avoid.
if lsof -ti:8090 >/dev/null 2>&1; then
    echo "Note: port 8090 is already in use, so an orchestrator is running somewhere." >&2
    echo "BI's Run will fail with 'Address already in use' until it is stopped." >&2
    echo >&2
fi

rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"

if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
fi
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
: "${PAYROLL_ADMIN_TOKEN:=}"
: "${PEOPLEOPS_STAFF_TOKEN:=}"

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Warning: ANTHROPIC_API_KEY is empty (checked .env and the environment)." >&2
    echo "The agents will start and serve their cards, but every model-backed" >&2
    echo "request will fail with an authentication error." >&2
    echo >&2
fi

# No fallback for either token: without a real value, that agent's
# extended-card auth gating (Payroll's AdminOnlyExtendedCardInterceptor,
# PeopleOperations' BearerTokenContextBuilder) stays permanently closed to
# every caller. Public skills and ordinary chat are unaffected.
if [ -z "$PAYROLL_ADMIN_TOKEN" ] || [ -z "$PEOPLEOPS_STAFF_TOKEN" ]; then
    echo "Note: PAYROLL_ADMIN_TOKEN and/or PEOPLEOPS_STAFF_TOKEN is unset -- see above." >&2
    echo "Set it in .env to test case-escalation or adjust-other-employee-payroll." >&2
    echo >&2
fi

# Writes a small runner script per agent (values baked in, since a new
# Terminal window starts a fresh shell that doesn't inherit this
# script's exported vars) and opens it in its own window.
open_terminal_window() {
    local slug="$1" title="$2"
    local runner="$RUN_DIR/$slug.sh"
    chmod +x "$runner"
    osascript <<OSA
tell application "Terminal"
    activate
    set newTab to do script "bash '$runner'"
    set custom title of newTab to "$title"
end tell
OSA
}

cat > "$RUN_DIR/parking.sh" <<EOF
cd "$ROOT_DIR/agents/parking"
[ -d .venv ] || { echo "building parking (uv sync)..."; uv sync; }
export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
echo "=== Parking — watching live ==="
exec .venv/bin/python3 __main__.py
EOF

cat > "$RUN_DIR/digiops.sh" <<EOF
cd "$ROOT_DIR/agents/digiops"
[ -d .venv ] || { echo "building digiops (uv sync)..."; uv sync; }
export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
echo "=== DigiOps — watching live ==="
exec .venv/bin/python3 __main__.py
EOF

cat > "$RUN_DIR/peopleoperations.sh" <<EOF
cd "$ROOT_DIR/agents/peopleoperations"
[ -d .venv ] || { echo "building peopleoperations (uv sync)..."; uv sync; }
export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
export PEOPLEOPS_STAFF_TOKEN="$PEOPLEOPS_STAFF_TOKEN"
echo "=== PeopleOperations — watching live ==="
exec .venv/bin/python3 __main__.py
EOF

cat > "$RUN_DIR/payroll.sh" <<EOF
cd "$ROOT_DIR/agents/payroll"
[ -f target/quarkus-app/quarkus-run.jar ] || { echo "building payroll (mvn package)..."; mvn -q -DskipTests -Dquarkus.analytics.disabled=true package; }
export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
export PAYROLL_ADMIN_TOKEN="$PAYROLL_ADMIN_TOKEN"
echo "=== Payroll — watching live ==="
exec java -jar target/quarkus-app/quarkus-run.jar
EOF

cat > "$RUN_DIR/travel_expense.sh" <<EOF
cd "$ROOT_DIR/agents/travel_expense"
[ -f target/quarkus-app/quarkus-run.jar ] || { echo "building travel_expense (mvn package)..."; mvn -q -DskipTests -Dquarkus.analytics.disabled=true package; }
export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
echo "=== Travel & Expense — watching live ==="
exec java -jar target/quarkus-app/quarkus-run.jar
EOF

open_terminal_window parking          "Parking"
open_terminal_window digiops          "DigiOps"
open_terminal_window peopleoperations "PeopleOperations"
open_terminal_window payroll          "Payroll"
open_terminal_window travel_expense   "Travel & Expense"

cat <<'DONE'

Opened 5 Terminal windows — one per downstream agent.
Each window IS that process's live output.

No orchestrator was started: port 8090 is left free for BI.

Next, once all five windows report ready:
  1. Open orchestrator/ in WSO2 Integrator: BI
  2. Run (or Debug), or use its chat panel

The orchestrator resolves all five agent cards at startup, so it will fail
with a connection error if you start it before the windows are ready.

To stop: Ctrl-C in each window, or close it.
DONE
