#!/bin/zsh
# Starts the three demo A2A agents (Weather 9201, Currency 9202, City Events 9203) and prints the secrets for the form.
# Ctrl+C stops them. --new-credentials makes a new password and token.
cd "$(dirname "$0")" || exit 1
[[ -d /Library/Java/JavaVirtualMachines/temurin-25.jdk ]] && export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home
python3 make-credentials.py $([[ "$1" == "--new-credentials" ]] && echo --force) || exit 1
echo "Building the demo agents..."
bal build >/dev/null || { bal build; exit 1; }
cat demo-credentials.txt
echo
echo "Agent Cards: http://localhost:9201/.well-known/agent-card.json  (9202, 9203 likewise)"
echo "Starting. Ctrl+C stops all three."
exec bal run target/bin/toolkit_demo_agents.jar
