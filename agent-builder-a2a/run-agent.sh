#!/bin/bash
# Builds and runs one demo agent, then shows the Agent Card it serves.
#   ./run-agent.sh [package]     default: recipe
# The card needs no model call. If ~/gitProject/a2a-library-testing/.env holds a key it is used (so chat works);
# otherwise a placeholder key lets the agent start and serve its card.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="${1:-recipe}"
cd "$HERE/$PKG"
ENV_FILE="$HOME/gitProject/a2a-library-testing/.env"
if [ -z "$BAL_CONFIG_DATA" ]; then
  if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi
  if [ -z "$BAL_CONFIG_DATA" ] && [ ! -f Config.toml ]; then
    export BAL_CONFIG_DATA='anthropicApiKey = "placeholder-key-card-only"'
  fi
fi
PORT=$(grep -oE "configurable int [A-Za-z0-9]+A2aPort = [0-9]+" main.bal | grep -oE "[0-9]+$" | head -1)
if [ -z "$PORT" ]; then echo "$PKG has no A2A server (no listener port in main.bal)."; exit 1; fi
bal build
java -jar "target/bin/$PKG.jar" &
AGENT_PID=$!
trap 'kill $AGENT_PID 2>/dev/null' EXIT INT TERM
CARD="http://localhost:$PORT/.well-known/agent-card.json"
for i in $(seq 1 30); do
  if curl -s -o /dev/null "$CARD"; then break; fi
  sleep 1
done
echo
echo "Agent Card served at: $CARD"
echo
curl -s "$CARD" | python3 -m json.tool
echo
if [ -z "$NO_OPEN" ]; then open "$CARD" 2>/dev/null || true; fi
echo "Running. Press Ctrl+C to stop."
wait $AGENT_PID
