#!/bin/bash
# Opens WSO2 Agent Builder (with the A2A server trigger and Use Remote Agent screens) in its own VS Code profile.
# Your normal VS Code and its extensions are not touched.
#   ./agent-builder-a2a.sh [folder]          open a package (default: recipe, next to this script)
#   ./agent-builder-a2a.sh --reinstall       reinstall the VSIX after a rebuild, then open
HERE="$(cd "$(dirname "$0")" && pwd)"
PROFILE="$HOME/.agent-builder-a2a"
VSIX="$HOME/gitProject/ballerina-vscode-a2a-demo/packages/ballerina-extension/ballerina-6.2.0-SNAPSHOT.vsix"
mkdir -p "$PROFILE/data" "$PROFILE/ext"
if [ "$1" = "--reinstall" ]; then
  shift
  code --user-data-dir "$PROFILE/data" --extensions-dir "$PROFILE/ext" --install-extension "$VSIX" --force
fi
DIR="${1:-$HERE/recipe}"
WSO2_PRODUCT_MODE=agent-builder exec code --user-data-dir "$PROFILE/data" --extensions-dir "$PROFILE/ext" --new-window "$DIR"
