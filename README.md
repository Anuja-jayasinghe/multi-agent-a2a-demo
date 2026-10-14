# A2A demos

Two demonstrations of [`ballerina/a2a`](https://github.com/ballerina-platform/module-ballerina-a2a), the Ballerina
implementation of the A2A (Agent2Agent) protocol.

| Demo | What it shows | Start here |
|---|---|---|
| [`multi-agent/`](multi-agent/) | The WSO2 Employee Concierge: one Ballerina orchestrator routing to five independent A2A agents written in different languages and frameworks, over every transport the client supports | [multi-agent/README.md](multi-agent/README.md) |
| [`operations-desk/`](operations-desk/) | One A2A agent written with the Ballerina listener (`service /rest on new a2a:HttpListener`), and one Ballerina AI chat agent that is its A2A client: two agents talking over A2A, driven from the chat panel or curl | [operations-desk/README.md](operations-desk/README.md) |

Each directory is self-contained, with its own README, configuration and `.gitignore`. Run commands from inside the demo you want.
