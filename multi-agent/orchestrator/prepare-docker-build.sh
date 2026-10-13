#!/usr/bin/env bash
# ballerina/a2a isn't published to Ballerina Central — it's a local-only
# package this repo depends on via `repository = "local"` in
# Ballerina.toml, pushed there from a sibling a2a-ballerina checkout
# (`bal pack && bal push --repository=local`). Docker's build context
# can't reach outside this directory, so this copies that already-pushed
# artifact into a staging directory the Dockerfile can COPY from — the
# same thing a real CI pipeline would do for an internal package not yet
# on a proper registry. Run this before `docker build` / `docker compose
# build` for the orchestrator image.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_REPO="$HOME/.ballerina/repositories/local/bala/ballerina/a2a"
STAGING_DIR="$ROOT_DIR/.docker-local-repo"

if [ ! -d "$LOCAL_REPO" ]; then
    echo "error: ballerina/a2a not found in the local Ballerina repository ($LOCAL_REPO)." >&2
    echo "Run 'bal pack && bal push --repository=local' from the a2a-ballerina checkout first." >&2
    exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -r "$LOCAL_REPO" "$STAGING_DIR/a2a"
echo "[ok] staged ballerina/a2a for the Docker build: $STAGING_DIR"
