# Agent naming — WSO2 internal alignment

Tracks generic demo names against their real WSO2-internal equivalents, so
renames can be applied in one pass later instead of getting lost piecemeal.

| Generic name (current) | WSO2 name | Status |
|---|---|---|
| HR Agent | **PeopleOperations** | Confirmed |
| IT Helpdesk Agent | **DigiOps** | Confirmed |
| Payroll Agent | ? | Pending |
| Parking Manager Agent | ? | Pending |
| Travel & Expense Agent | ? | Pending |
| Employee Concierge (orchestrator) | ? | Pending — may stay generic |

When a pending name is confirmed: update this table, then grep the repo for
the generic name and rename in code, agent cards, docs, and `DEMO_SCRIPT.md`
in one pass.
