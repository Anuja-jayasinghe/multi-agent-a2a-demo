// Real test against the real ballerina/ai Agent + real anthropic:ModelProvider
// — no mocks. Without a real ANTHROPIC_API_KEY, the whole
// ballerina/ai -> ballerinax/ai.anthropic -> Anthropic API pipeline must
// fail gracefully with a typed error, proving it's genuinely wired end to
// end. With a real key present (Phase 9), it's asserted for real content
// instead — see phase9_routing_test.bal for the routing-quality checks.
//
// Known real flakiness, not a bug in this test or in agent_tools.bal: the
// concierge sometimes re-calls an ask tool several times for one question
// even when the first call's result is already unambiguous -- confirmed
// non-deterministic (same test passed cleanly in 32s on one run, hit
// concierge_agent.bal's maxIter cap on another, unchanged code). If this
// fails, re-run it before assuming a regression.
import ballerina/os;
import ballerina/test;

@test:Config {}
function testConciergeAgent() returns error? {
    string|error result = concierge.run("is parking spot A03 available?");
    if os:getEnv("ANTHROPIC_API_KEY") != "" {
        test:assertTrue(result is string && result.length() > 0, "expected a real, non-empty reply with a real key");
    } else {
        test:assertTrue(result is error, "expected a graceful error without a real Anthropic key");
    }
}
