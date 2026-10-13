# Agent cheat sheet

What each of the five agents behind the orchestrator can actually do,
in plain language — for figuring out what to ask when demoing or
testing the chat.

## What changed

Every write action (reserving parking, raising a ticket, filing a
correction or claim) now asks for the employee's real name if it
doesn't already have one, and remembers it for the rest of the
conversation. Once given, that name is really stored and really
answerable back — "who reserved spot A02?", "who raised that ticket?"
now get real answers instead of a privacy refusal.

The chat used to only be able to send a message and get a reply — no
cancelling, no checking status, no listing. That's fixed too: every
agent now has real cancel/status/list tools wired into the chat, on
top of the original ask tool. When a request creates something, the
reply includes a real task id; mention it back later ("cancel that",
"check on it") and the chat will recall it and act on the real thing.

One real limit worth knowing: "list" shows *every* task that agent has
ever seen, not filtered to just you — there's no login/identity
concept, just whatever name was given per request. In a single-person
demo that's effectively fine, but it's "everyone's," not "yours."

Also still true: push notifications ("let me know when it's approved")
aren't a chat capability — that needs a webhook target of your own.

## A real, disclosed reliability quirk

The chat's tool-calling can misbehave in two different directions, both
confirmed non-deterministic and not fixable by prompt wording alone
(each reproduced down to a single tool and a one-sentence prompt and it
still happened sometimes) — real architecture details in
[GitHub issue #24](https://github.com/Anuja-jayasinghe/multi-agent-a2a-demo/issues/24):

- **Redundant repeat** — occasionally re-calls a tool several times for
  one simple question, even when the first call already had a clear
  answer. Switching from twenty named tools to five generic ones (see
  `orchestrator/README.md`) measurably reduced how often this happens
  in re-testing, but didn't fully eliminate it.
- **Skipped call** — occasionally answers a status/cancel/list question
  from earlier conversation context instead of making the required
  fresh tool call, effectively repeating a stale answer as if it were
  current. Confirmed live in a real chat session (a status check for an
  in-progress onboarding was answered from memory, then a genuine
  cancel attempt on the same task correctly failed because the task had
  actually finished by then — the two replies looked contradictory, but
  the real cause was the skipped status check, not a cancellation bug).
  The system prompt now states this as two explicit rules rather than
  one combined sentence, to give the model less room to satisfy the
  letter of the guardrail while missing one direction of it.

There's a bounded retry cap in place so a bad run fails fast with a
clear error instead of hanging indefinitely; if a question fails this
way, just ask it again.

---

## Parking
Spot availability and reservations at WSO2 Colombo HQ — day-scoped, so a
spot free today may be taken tomorrow and vice versa.

✅ Ask:
- "is anything free?" / "is there any parking available?" (defaults to today)
- "is spot A01 free tomorrow?" (a spot's status is genuinely per-day, not global)
- "reserve spot A01 for tomorrow" (it'll ask your name first, if it doesn't
  have it; defaults to today if no date is given)
- "reserve me a spot on level 2" (it'll ask which exact spot too)
- "who reserved spot A02 today?"
- "cancel that" (right after a reservation, in the same conversation —
  works while it's still pending)
- "list my reservations" (a real per-employee lookup, across all dates)
- "cancel my A03 reservation" (a real cancel for an already-completed
  reservation, genuinely frees the spot back up for that date — not just
  the mid-flight `cancelTask` above)
- "what have I reserved so far?" (lists every reservation attempt, not just yours)

❌ Can't:
- Reserve more than one spot in a single message

---

## DigiOps (IT Helpdesk)
VPN, password resets, hardware requests, and IT incidents.

✅ Ask:
- "how do I reset my VPN password?"
- "I need a new laptop" (standard catalog — laptop, monitor, docking
  station, headset — fulfills fast, no staged wait, matching what a real
  in-stock request would do)
- "I need a new laptop charger" (outside the standard catalog — opens a
  real ticket with an ID, then genuinely takes ~10 real minutes to work
  through manager approval and fulfillment, staying open the whole time;
  the ticket itself is created right away)
- "who raised ticket X?"
- "what's the status of that ticket?" (recalls the id from the conversation
  — while it's still being fulfilled, this gives a real "still working"
  answer, not a fake instant "done")
- "list all my tickets" (real per-employee lookup via `list_my_tickets`,
  not just everyone's)
- "close ticket X, I got the item" (a real status change, not cosmetic —
  tickets otherwise stay frozen at their fulfilled/pending state forever)
- "cancel that ticket" (a real mid-fulfillment cancel, not just deleting a
  record)
- "my laptop can't reach the internal network" (investigates, gives a diagnosis)
- "what tickets have been raised?" (lists every one this agent knows about)

❌ Can't:
- Anything outside IT (payroll, parking, etc.) — the orchestrator won't route it here anyway

---

## PeopleOperations (HR)
Leave policy, benefits, new-hire onboarding, offboarding, and leave filing.

✅ Ask:
- "how many annual leave days do I have?"
- "what benefits am I eligible for?"
- "onboard Jane Doe as a new hire" (runs a real ~10-minute provisioning
  flow — laptop, desk, benefits, one staged step at a time — not a fake
  instant confirmation)
- "offboard Jane Doe" (the same real staged flow in reverse — laptop
  revoked, desk freed, benefits terminated — its own
  `OFFBOARDING_STEP_DELAY_SECONDS`, independently timed from onboarding)
- "what's the status of that onboarding?" (a real, honest in-progress
  answer while it's still running, not just at the end — backed by a real
  `check_onboarding_status` tool call, not the LLM's own recollection)
  / "cancel it" (a real mid-flight cancel)
- "what onboardings have been run?"
- "file leave for Jane Doe from 2026-09-01 to 2026-09-03 for a family
  event" (a real leave request, not just a policy recitation)

❌ Can't:
- Escalate a case to a human — that skill exists on the agent but needs a
  staff login token the orchestrator doesn't have, so it's invisible from chat

---

## Payroll
Payslip questions, corrections, pay history, and tax documents.

✅ Ask:
- "when is the next pay date?"
- "my payslip has the wrong amount" (asks your name, then files a real
  correction request with an ID -- it then genuinely goes through a
  staged review, `submitted` → `in_review` → `approved`, not an instant
  fake approval)
- "what's the status of my correction?" (a real, honest `in_review`
  answer while it's still being reviewed) / "cancel it" (a real
  mid-review cancel)
- "what corrections have been filed?"
- "what's my pay history?" (a real 3-month lookup)
- "I need my tax certificate for 2025" (a real tax-document request with
  a reference number)

❌ Can't:
- Adjust someone *else's* payroll — that's an admin-only skill the orchestrator
  can't unlock (needs an admin token it doesn't have)

---

## Travel & Expense
Travel policy questions, per-diem calculations, and expense claims.

✅ Ask:
- "what's the per-diem rate?"
- "what's the per diem for 4 days in Europe?" (a real calculation via
  `calculatePerDiem`, not just the quoted rate)
- "I spent 45.50 USD on a taxi to the airport, my name is X" (a real,
  structured amount + currency, not a free-text blob -- files a claim
  with an ID that resolves fast, since it's an ordinary expense)
- "I spent 120 USD on a client dinner, my name is X" (client entertainment
  genuinely triggers a staged manager review before it's approved -- an
  honest status check on it may still say `in_review` for a while)
- "what's the status of my claim?" (always a fresh, real check) / "cancel it"
- "what claims have been filed?"

❌ Can't:
- Anything about actual travel booking (flights, hotels) — this agent only handles
  policy questions and expense claims, not booking

---

## One more thing

All the data behind these agents (spots, tickets, payslips, claims,
and now names) is fake and lives in memory — it resets every time an
agent restarts. This is a demo, not a connection to any real WSO2
system.
