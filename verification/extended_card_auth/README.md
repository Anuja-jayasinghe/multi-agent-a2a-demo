# Extended card auth — end-to-end use case

Proves that a client starting with **nothing but a URL** can work out which
credential a guarded skill needs, supply it by scheme name, and unlock the
agent's extended card — without anyone hardcoding a header name or being
told out of band which token goes where.

Exercises `ballerina/a2a`'s card-driven credential support against the
real, running PeopleOperations agent. No mocks.

## Run it

```bash
# 1. Start the agent. A working ANTHROPIC_API_KEY is needed for steps 7-8
#    (they exercise real model-backed tasks); steps 1-6 are pure card and
#    auth logic and pass without one — those two report [skip] instead.
cd agents/peopleoperations
PEOPLEOPS_STAFF_TOKEN=demo-staff-secret uv run __main__.py

# 2. In another terminal:
cd verification/extended_card_auth
bal run --sticky
```

`--sticky` is required. See `Ballerina.toml` for why the `grpc` version is
pinned.

## What it covers

| Step | What it proves |
|---|---|
| 1 | The card declares `securitySchemes`/`securityRequirements`, and they parse from the real v1.0 wire form (`{"schemes": {...}}`, not the flat v0.3 shape) |
| 2 | `skillSecurityRequirements` — a guarded skill's own requirement, a public skill inheriting the card-level one, and a typed `Error` for an unknown skill id |
| 3 | `resolveSecuritySchemes` — turning the arbitrary name `"bearer-staff"` into a concrete `HttpAuthSecurityScheme`, and reporting a requirement that names an undeclared scheme |
| 4 | The payoff: the scheme name discovered in step 3 is fed straight into an `InMemoryCredentialStore`, and the resulting client gets the full extended card (3 skills vs. the anonymous 2) |
| 5 | Negatives — a wrong credential is genuinely rejected; a credential filed under an undeclared scheme name is never sent; an empty provider sends the request bare rather than failing; and a credential replaced on a **live** client takes effect immediately |
| 6 | The provider and the older explicit-`headers` route produce identical results, and an explicit header still wins over a card-resolved one |
| 7 | Ordinary traffic still works for a credentialled client, and `isAuthorizationRequired`/`authorizationPrompt` read a real model-backed `Task` correctly |
| 8 | **The gate that matters**: asking for the guarded skill *by name* is refused for an unauthenticated caller and succeeds for an authenticated one |

Two steps are worth reading closely.

**Step 4** — nothing after step 3 mentions `Authorization`, `Bearer`, or
`bearer-staff` as a literal. The scheme name comes from the card itself.

**Step 8** — card gating only controls whether a skill is *advertised*.
Spec section 13.1 requires the server to authorize the request itself, so
this step ignores the card entirely and simply asks for `case-escalation`
by name from both sides. Unauthenticated gets a real refusal
("staff-only ... credentials ... not provided") and no case is created;
authenticated gets a real case ID. Verified stable across repeated runs
rather than a single lucky pass.

## What this required on the agent side

PeopleOperations previously gated `case-escalation` behind a bearer token
but declared **no** `securitySchemes` at all, so a client could see the
skill existed and still have no protocol-level way to learn what unlocked
it. `agents/peopleoperations/__main__.py` now declares the scheme and
attaches the requirement at both card and skill level, which is what makes
the discovery in steps 1–3 possible.
