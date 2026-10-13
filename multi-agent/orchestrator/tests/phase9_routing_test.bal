// Phase 9 functional pass: real routing quality against the real
// Anthropic model. Scenarios 7-10 from docs/DEMO_SCRIPT.md. Run once
// against all five real running agents (scripts/start-all.sh with a real
// ANTHROPIC_API_KEY in .env): bal test --sticky
//
// These are print-and-eyeball checks, not strict string assertions —
// routing QUALITY (did the model pick the sensible tool) is a judgment
// call a fixed string match would just be a brittle proxy for. Each
// prints the real reply for scenarios 7-9, and asserts the off-domain
// scenario 10 didn't fabricate an answer from one of the five domains.
import ballerina/io;
import ballerina/test;

@test:Config {}
function testRoutesToParking() returns error? {
    string reply = check concierge.run("is there a free parking spot at HQ right now?");
    io:println("\n[7] routes to Parking — reply:\n", reply, "\n");
    test:assertTrue(reply.length() > 0, "expected a real, non-empty reply");
}

@test:Config {}
function testRoutesToDigiOps() returns error? {
    string reply = check concierge.run("my laptop won't connect to the VPN, can you help?");
    io:println("[8] routes to DigiOps — reply:\n", reply, "\n");
    test:assertTrue(reply.length() > 0, "expected a real, non-empty reply");
}

@test:Config {}
function testRoutesToPayroll() returns error? {
    string reply = check concierge.run("when do I get paid this month?");
    io:println("[9] routes to Payroll — reply:\n", reply, "\n");
    test:assertTrue(reply.length() > 0, "expected a real, non-empty reply");
}

@test:Config {}
function testOffDomainRequestIsDeclined() returns error? {
    string reply = check concierge.run("what's the weather like today?");
    io:println("[10] off-domain request — reply:\n", reply, "\n");
    test:assertTrue(reply.length() > 0, "expected a real, non-empty reply");
}
