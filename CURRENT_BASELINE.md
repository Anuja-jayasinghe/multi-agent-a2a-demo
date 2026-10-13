# Current dependency baseline

The active agents in this demo now use:

- Python `a2a-sdk` 1.2.1 where the dependency is locked explicitly or
  resolved through `uv.lock`.
- Java `a2a-java` 1.4.0.Final for the Payroll and Travel & Expense agents.
- Ballerina `a2a` 0.2.1 for the multi-transport client and verification
  projects.
- Ballerina `ai` 1.14.0, retained deliberately because this demo uses the
  original hand-written orchestrator tool layer. The newer one-toolkit-per-
  agent design is maintained and tested in `a2a-ai-toolkit` and
  `wso2-integrator-a2a`; migrating this demo to that design is a separate
  architectural change, not a dependency-only update.

Historical research and demo transcripts retain the dependency versions that
were in effect when those experiments ran.
