#!/usr/bin/env bash
# Stops everything holding a demo port, whatever started it, and frees the
# ports.
#
# scripts/stop-all.sh only knows about PIDs that scripts/start-all.sh
# recorded in .pids/. That leaves three common cases it cannot stop:
#
#   - agents opened by watch-agents-local.sh / watch-agents-for-bi.sh,
#     which deliberately track no PIDs (each lives in its own window)
#   - an orchestrator launched from WSO2 Integrator: BI's Run or Debug
#   - anything started by hand
#
# All three still hold a port, so this works from the ports instead of a
# PID file. That is also why it is the one to reach for after a
# 'failed to start server connector 0.0.0.0:8090: Address already in use'.
#
# Terminal windows opened by the watch-agents scripts are left open; their
# process exits and the shell returns to a prompt. Close them yourself.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Every port the demo binds: five agents, Payroll's extra gRPC port, and
# the orchestrator's service + webhook receiver.
PORTS=(8000 8001 8002 8003 8004 9003 8090 9090)

# The IDE itself also listens locally (its OTLP trace collector on 59500,
# among others). Killing that would take down the editor rather than an
# agent, so any process whose command names the app shell is skipped --
# while the orchestrator BI launches, which runs from the *bundled
# Ballerina runtime* inside the same app bundle, is still fair game.
is_ide_process() {
    local cmd="$1"
    case "$cmd" in
        *"WSO2 Integrator.app/Contents/MacOS/Electron"*) return 0 ;;
        *"WSO2 Integrator Helper"*) return 0 ;;
        *"Visual Studio Code"*|*"Code Helper"*) return 0 ;;
        *) return 1 ;;
    esac
}

declare -a TARGETS=()
for port in "${PORTS[@]}"; do
    while read -r pid; do
        [ -n "$pid" ] || continue
        cmd="$(ps -p "$pid" -o command= 2>/dev/null)"
        [ -n "$cmd" ] || continue
        if is_ide_process "$cmd"; then
            echo "skipping pid $pid on port $port — that is the IDE, not an agent"
            continue
        fi
        # One process can hold several ports (Payroll 8003+9003, the
        # orchestrator 8090+9090), so collect uniquely.
        case " ${TARGETS[*]-} " in
            *" $pid "*) ;;
            *) TARGETS+=("$pid") ;;
        esac
    done < <(lsof -ti:"$port" 2>/dev/null)
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "Nothing to stop — no demo port is in use."
else
    echo "Stopping ${#TARGETS[@]} process(es):"
    for pid in "${TARGETS[@]}"; do
        printf '  pid %-7s %s\n' "$pid" "$(ps -p "$pid" -o command= 2>/dev/null | cut -c1-72)"
    done

    # Ask first: these are real servers, and a clean shutdown lets them
    # close listeners and finish in-flight responses.
    for pid in "${TARGETS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    sleep 4

    # Then insist, but only for whatever ignored the request.
    for pid in "${TARGETS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "  pid $pid did not exit on TERM — sending KILL"
            kill -9 "$pid" 2>/dev/null
        fi
    done
    sleep 1
fi

# start-all.sh's bookkeeping, cleared so a later stop-all.sh does not
# report stale entries it can no longer find.
if [ -d "$ROOT_DIR/.pids" ]; then
    rm -f "$ROOT_DIR/.pids"/*.pid 2>/dev/null
fi

echo
STILL_BUSY=""
for port in "${PORTS[@]}"; do
    if lsof -ti:"$port" >/dev/null 2>&1; then
        STILL_BUSY="$STILL_BUSY $port"
    fi
done

if [ -n "$STILL_BUSY" ]; then
    echo "Still in use:$STILL_BUSY" >&2
    for port in $STILL_BUSY; do
        for pid in $(lsof -ti:"$port" 2>/dev/null); do
            printf '  port %-5s pid %-7s %s\n' "$port" "$pid" \
                "$(ps -p "$pid" -o command= 2>/dev/null | cut -c1-64)" >&2
        done
    done
    exit 1
fi

echo "All demo ports free: ${PORTS[*]}"
