#!/usr/bin/env bash
# Confirms the containerized system (docker-compose.yml) behaves the same
# as the local-process one — card resolution and a real sendMessage
# round-trip against Parking, all over Docker's internal DNS, run from
# inside the compose network (docker-compose service names like "parking"
# don't resolve from the host). No Anthropic key needed or spent.
#
# Prerequisite: `docker compose up -d` already running.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARITY_DIR="$ROOT_DIR/verification/docker_parity"
NETWORK="$(basename "$ROOT_DIR")_default"

unset JAVA_HOME
# Seed from orchestrator's committed, known-good lock file rather than
# resolving fresh — a fresh resolve of this a2a+http combo has proven
# non-deterministic before, occasionally picking an http version that
# conflicts with grpc at runtime (ballerina-platform/ballerina-library#2496).
cp "$ROOT_DIR/orchestrator/Dependencies.toml" "$PARITY_DIR/Dependencies.toml"
( cd "$PARITY_DIR" && rm -rf target && bal build --sticky )

docker run --rm \
    --network "$NETWORK" \
    -v "$PARITY_DIR:/work" \
    -w /work \
    ballerina/ballerina:2201.13.5 \
    bal run target/bin/verify_docker_parity.jar
