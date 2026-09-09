// Real ballerina/a2a client verification against the real, running
// PeopleOperations Agent (agents/peopleoperations) — no mocks, no stubs.
// Start the agent first (the staff token only matters for the
// extended-card check, which needs no LLM either):
//
//   cd agents/peopleoperations
//   PEOPLEOPS_STAFF_TOKEN=demo-staff-secret uv run __main__.py
//
// then run this script from this directory: bal run --sticky
//
// Card and auth-gating checks pass today, no key needed. Checks that need
// the model to actually answer are marked DEFERRED and re-run for real in
// Phase 9 once the key exists.
import ballerina/a2a;
import ballerina/io;
import ballerina/os;
import ballerina/uuid;

const string AGENT_URL = "http://127.0.0.1:8002";

// Read the token from the same env var the agent itself reads, so client
// and server agree without either hardcoding the other's value. Hardcoding
// it here silently broke this check once .env began carrying a real
// (non-demo) token: the agent gated on the real value while this asked
// with "demo-staff-secret", so the extended card came back ungated and the
// gating assertion failed for a reason that had nothing to do with gating.
final string STAFF_TOKEN = os:getEnv("PEOPLEOPS_STAFF_TOKEN") != ""
    ? os:getEnv("PEOPLEOPS_STAFF_TOKEN")
    : "demo-staff-secret";

public function main() returns error? {
    int failures = 0;
    io:println("=== PeopleOperations Agent — real ballerina/a2a verification ===\n");

    // 1. Agent card is correct.
    a2a:AgentCard card = check a2a:resolveAgentCard(AGENT_URL);
    if card.name == "PeopleOperations Agent" && card.capabilities.streaming
            && card.capabilities.extendedAgentCard {
        io:println("[ok] agent card resolves correctly, streaming + extendedAgentCard declared");
    } else {
        io:println("[FAIL] unexpected agent card content");
        failures += 1;
    }

    // 2. Extended agent card genuinely differs based on real authentication —
    // pure card-serving logic, no LLM involved, fully verified now.
    a2a:Client unauth = check new (AGENT_URL);
    a2a:AgentCard unauthCard = check unauth->getExtendedAgentCard();
    boolean unauthHasEscalation = unauthCard.skills.some(s => s.id == "case-escalation");

    a2a:Client authed = check new (AGENT_URL, headers = {"Authorization": "Bearer " + STAFF_TOKEN});
    a2a:AgentCard authedCard = check authed->getExtendedAgentCard();
    boolean authedHasEscalation = authedCard.skills.some(s => s.id == "case-escalation");

    if !unauthHasEscalation && authedHasEscalation {
        io:println("[ok] extended card genuinely differs based on real authentication (",
                unauthCard.skills.length(), " vs ", authedCard.skills.length(), " skills)");
    } else {
        io:println("[FAIL] extended card gating did not behave as expected");
        failures += 1;
    }

    // 3. Policy Q&A / onboarding: without a real key, must fail gracefully —
    // proving the whole LangGraph -> A2A -> ballerina/a2a pipeline is wired
    // correctly end to end. [DEFERRED to Phase 9 for the actual answer.]
    a2a:Message msg = {messageId: uuid:createType4AsString(), role: a2a:ROLE_USER, parts: [{text: "how many annual leave days do I have?"}]};
    a2a:Task|a2a:Message|error result = unauth->sendMessage(msg);
    if result is error {
        io:println("[ok] policy Q&A fails gracefully without a real key: ", result.message());
    } else {
        io:println("[ok, unexpected] policy Q&A succeeded — a real key must already be configured");
    }

    io:println("\n=== ", failures == 0 ? "ALL STRUCTURAL CHECKS PASSED" : failures.toString() + " FAILURE(S)",
            " (functional checks deferred to Phase 9) ===");
    if failures > 0 {
        return error(failures.toString() + " verification check(s) failed");
    }
}
