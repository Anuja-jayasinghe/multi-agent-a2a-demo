#!/usr/bin/env bash
# Opens one Terminal.app window per agent, plus one for the orchestrator,
# each running its real process in the *foreground* -- so every window
# IS that agent's live log: you watch it receive a task, work on it, and
# send the response back, in real time. Unlike scripts/start-all.sh,
# nothing here is backgrounded or redirected to logs/*.log.
#
# macOS + Terminal.app only. Ctrl-C in a window stops that one agent;
# closing the window does the same. This doesn't track PIDs the way
# start-all.sh/stop-all.sh do, since each process lives in its own
# foreground window on purpose.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT_DIR/.watch-agents"
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
# No fallback for either: without a real value, that agent's extended-card
# auth gating (Payroll's AdminOnlyExtendedCardInterceptor, PeopleOperations'
# BearerTokenContextBuilder) stays permanently closed to every caller --
# set it in .env to test case-escalation or adjust-other-employee-payroll.
# Everything else -- public skills, ordinary chat -- is unaffected.
if [ -z "$PAYROLL_ADMIN_TOKEN" ] || [ -z "$PEOPLEOPS_STAFF_TOKEN" ]; then
    echo "Note: PAYROLL_ADMIN_TOKEN and/or PEOPLEOPS_STAFF_TOKEN is unset -- see above." >&2
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

cat > "$RUN_DIR/orchestrator.sh" <<EOF
cd "$ROOT_DIR/orchestrator"
unset JAVA_HOME
[ -f target/bin/orchestrator.jar ] || { echo "building orchestrator (bal build --sticky)..."; bal build --sticky; }
export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
echo "=== Orchestrator — watching live ==="
exec bal run target/bin/orchestrator.jar
EOF

open_terminal_window parking          "Parking"
open_terminal_window digiops          "DigiOps"
open_terminal_window peopleoperations "PeopleOperations"
open_terminal_window payroll          "Payroll"
open_terminal_window travel_expense   "Travel & Expense"
# Give the five downstream agents a head start so the orchestrator's own
# window doesn't fill up with connection-refused noise while they boot.
sleep 2
open_terminal_window orchestrator     "Orchestrator"

echo "Opened 6 Terminal windows — one per agent, one for the orchestrator."
echo "Each window IS that process's live output."
echo
echo "Once all six say ready, test the client:"
echo '  curl -s http://127.0.0.1:8090/concierge/chat -H "Content-Type: application/json" \'
echo '    -d '"'"'{"sessionId":"test","message":"is there parking available today?"}'"'"
