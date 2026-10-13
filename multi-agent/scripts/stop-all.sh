#!/usr/bin/env bash
# Stops every process scripts/start-all.sh started, using the PIDs it
# recorded in .pids/.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_DIR="$ROOT_DIR/.pids"

if [ ! -d "$PID_DIR" ]; then
    echo "nothing to stop — $PID_DIR does not exist"
    exit 0
fi

for pid_file in "$PID_DIR"/*.pid; do
    [ -e "$pid_file" ] || continue
    name="$(basename "$pid_file" .pid)"
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo "stopped $name (pid $pid)"
    else
        echo "$name (pid $pid) was already gone"
    fi
    rm -f "$pid_file"
done
