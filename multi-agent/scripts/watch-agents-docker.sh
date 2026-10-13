#!/usr/bin/env bash
# Opens one Terminal.app window per service, each tailing
# `docker compose logs -f <service>` -- so you can watch every
# containerized agent receive a task, work on it, and respond, without
# leaving Docker's own detached, terminal-less containers.
#
# macOS + Terminal.app only. This only *watches* an already-running
# stack -- start one first with:
#   docker compose up -d --build --wait
# Ctrl-C in a window only stops watching that service's logs; the
# container itself keeps running (`docker compose down` stops those).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT_DIR/.watch-agents"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"

export PATH="$HOME/.rd/bin:$PATH"
cd "$ROOT_DIR"

if ! docker compose ps --status running --format '{{.Name}}' 2>/dev/null | grep -q .; then
    echo "error: no containers are running. Start the stack first:" >&2
    echo "  docker compose up -d --build --wait" >&2
    exit 1
fi

open_terminal_window() {
    local slug="$1" title="$2" service="$3"
    local runner="$RUN_DIR/$slug.sh"
    cat > "$runner" <<EOF
export PATH="\$HOME/.rd/bin:\$PATH"
cd "$ROOT_DIR"
echo "=== $title — live logs ==="
exec docker compose logs -f $service
EOF
    chmod +x "$runner"
    osascript <<OSA
tell application "Terminal"
    activate
    set newTab to do script "bash '$runner'"
    set custom title of newTab to "$title"
end tell
OSA
}

open_terminal_window parking          "Parking"          parking
open_terminal_window digiops          "DigiOps"          digiops
open_terminal_window peopleoperations "PeopleOperations" peopleoperations
open_terminal_window payroll          "Payroll"          payroll
open_terminal_window travel_expense   "Travel & Expense" travel_expense
open_terminal_window orchestrator     "Orchestrator"     orchestrator

echo "Opened 6 Terminal windows, each tailing one service's live logs."
echo
echo "Test the client:"
echo '  curl -s http://127.0.0.1:8090/concierge/chat -H "Content-Type: application/json" \'
echo '    -d '"'"'{"sessionId":"test","message":"is there parking available today?"}'"'"
