// Real bal test suite exercising the five generic tool functions
// directly — no mocks. Start all five real agent processes before
// running `bal test`. Unlike the old per-agent `final a2a:Client`
// module vars, no agent's card is resolved until a test actually
// delegates to it, so (unlike before) this package can still start
// with some agents down — individual tests against those agents will
// just fail instead of the whole suite refusing to run.
//
// All five agents are real LLM-backed agents and need a real Anthropic
// key to answer meaningfully via delegateToAgent: with ANTHROPIC_API_KEY
// unset, they're asserted to fail gracefully — proof the tool ->
// ballerina/a2a -> real agent wire is genuinely connected, not a bypass.
// With a real key present (Phase 9), they're asserted for real,
// non-empty content instead — see docs/DEMO_SCRIPT.md for the actual
// real answers these produced.
import ballerina/os;
import ballerina/test;
import ballerina/uuid;

final boolean hasRealKey = os:getEnv("ANTHROPIC_API_KEY") != "";

// Pulls the real task id embedded in a delegateToAgent/getAgentTaskStatus
// reply (see summarizeTask in agent_tools.bal: "... (task id: <id>)").
isolated function extractTaskIdFromReply(string reply) returns string? {
    int? startIdx = reply.indexOf("(task id: ");
    if startIdx is () {
        return ();
    }
    string tail = reply.substring(startIdx + "(task id: ".length());
    int? endIdx = tail.indexOf(")");
    if endIdx is () {
        return ();
    }
    return tail.substring(0, endIdx);
}

// A realistic-sounding base name, matching this demo's existing
// WSO2-Colombo flavor (see Parking/DigiOps' own live-verification
// fixtures). Each test's employee name still needs to be unique across
// repeated bal test runs against the same long-lived agent process (e.g.
// Parking's day-scoped reservations, DigiOps' ticket store), but a raw
// UUID suffix on an obviously-synthetic base like "Task Lifecycle Test"
// sometimes gets the LLM to correctly-but-inconveniently judge it "doesn't
// look like an actual person's name" and ask for clarification instead of
// proceeding -- a real, observed flake (see Finding 4,
// docs/research/a2a-client-and-demo-round-check.md). A real first+last
// name with a short numeric tag reads as a real name in practice far more
// reliably than a test-fixture-shaped string does.
isolated function uniqueTestEmployeeName() returns string {
    return "Kasun Silva " + uuid:createType4AsString().substring(0, 4);
}

@test:Config {}
function testDiscoverAgents() returns error? {
    json cards = check discoverAgents();
    json[] cardArray = check cards.ensureType();
    test:assertEquals(cardArray.length(), 5, "expected a card entry for every known agent");
}

@test:Config {}
function testDelegateToUnknownAgent() returns error? {
    string|error result = delegateToAgent("NotARealAgent", "hello?");
    test:assertTrue(result is error, "expected a graceful error for an unknown agent name");
}

@test:Config {}
function testDelegateToParking() returns error? {
    string|error result = delegateToAgent("Parking", "is spot A03 available?");
    if hasRealKey {
        test:assertTrue(result is string && result.length() > 0, "expected a real, non-empty reply with a real key");
    } else {
        test:assertTrue(result is error, "expected a graceful error without a real Anthropic key");
    }
}

@test:Config {}
function testDelegateToDigiOps() returns error? {
    string|error result = delegateToAgent("DigiOps", "how do I reset my VPN password?");
    if hasRealKey {
        test:assertTrue(result is string && result.length() > 0, "expected a real, non-empty reply with a real key");
    } else {
        test:assertTrue(result is error, "expected a graceful error without a real Anthropic key");
    }
}

@test:Config {}
function testDelegateToPeopleOperations() returns error? {
    string|error result = delegateToAgent("PeopleOperations", "how many annual leave days do I have?");
    if hasRealKey {
        test:assertTrue(result is string && result.length() > 0, "expected a real, non-empty reply with a real key");
    } else {
        test:assertTrue(result is error, "expected a graceful error without a real Anthropic key");
    }
}

@test:Config {}
function testDelegateToPayroll() returns error? {
    string|error result = delegateToAgent("Payroll", "when is the next pay date?");
    if hasRealKey {
        test:assertTrue(result is string && result.length() > 0, "expected a real, non-empty reply with a real key");
    } else {
        test:assertTrue(result is error, "expected a graceful error without a real Anthropic key");
    }
}

@test:Config {}
function testDelegateToTravelExpense() returns error? {
    string|error result = delegateToAgent("TravelExpense", "what's the per-diem rate?");
    if hasRealKey {
        test:assertTrue(result is string && result.length() > 0, "expected a real, non-empty reply with a real key");
    } else {
        test:assertTrue(result is error, "expected a graceful error without a real Anthropic key");
    }
}

// cancelAgentTask/getAgentTaskStatus/listAgentTasks never touch the LLM --
// pure a2a:Client calls -- so these run unconditionally, no key needed.
// One representative agent per transport binding (Parking: REST, DigiOps:
// JSON-RPC, Payroll: gRPC) is enough to prove the shared
// cancelTaskOn/getTaskStatusOn/listTasksOn helpers work over each real
// wire; the other two agents share the same helpers.

@test:Config {}
function testListParkingTasks() returns error? {
    string result = check listAgentTasks("Parking");
    test:assertTrue(result.length() > 0, "expected a real, non-empty summary (even if it's just \"No tasks found.\")");
}

@test:Config {}
function testGetParkingTaskStatusUnknownId() returns error? {
    string|error result = getAgentTaskStatus("Parking", "does-not-exist");
    test:assertTrue(result is error, "expected a graceful error for an unknown task id");
}

@test:Config {}
function testCancelParkingTaskUnknownId() returns error? {
    string|error result = cancelAgentTask("Parking", "does-not-exist");
    test:assertTrue(result is error, "expected a graceful error for an unknown task id");
}

@test:Config {}
function testListDigiOpsTasks() returns error? {
    string result = check listAgentTasks("DigiOps");
    test:assertTrue(result.length() > 0, "expected a real, non-empty summary (even if it's just \"No tasks found.\")");
}

@test:Config {}
function testListPayrollTasks() returns error? {
    string result = check listAgentTasks("Payroll");
    test:assertTrue(result.length() > 0, "expected a real, non-empty summary (even if it's just \"No tasks found.\")");
}

// The four tests below exercise the real long-running task lifecycle
// (onboarding, hardware provisioning, Parking's reservation flow) added on
// top of the discover-and-delegate tools. Onboarding/provisioning steps
// default to ~200s each -- far longer than sendToAgent's own 20s poll
// window (agent_tools.bal), so delegateToAgent is guaranteed to time out
// into a real "still working" reply within ~20s, not the full ~10 minutes.
// No env var override is needed for these two assertions specifically (a
// shorter delay would actually make the "still WORKING" assertion racy,
// since it could complete inside the 20s poll window instead).

@test:Config {enable: hasRealKey}
function testOnboardingStartsAsBackgroundTask() returns error? {
    string employeeName = uniqueTestEmployeeName();
    string reply = check delegateToAgent("PeopleOperations", "onboard " + employeeName + " as a new hire");
    test:assertFalse(reply.startsWith("[TASK_STATE_COMPLETED]"),
            "onboarding takes real minutes -- it should not complete within the 20s poll window: " + reply);
    string? taskId = extractTaskIdFromReply(reply);
    test:assertTrue(taskId is string, "expected a real task id in the still-in-progress reply: " + reply);
    if taskId is string {
        string status = check getAgentTaskStatus("PeopleOperations", taskId);
        test:assertTrue(status.startsWith("[TASK_STATE_WORKING]") || status.startsWith("[TASK_STATE_SUBMITTED]"),
                "expected the task to genuinely still be in progress: " + status);
    }
}

@test:Config {enable: hasRealKey}
function testCancelOnboardingMidFlight() returns error? {
    string employeeName = uniqueTestEmployeeName();
    string reply = check delegateToAgent("PeopleOperations", "onboard " + employeeName + " as a new hire");
    string? taskId = extractTaskIdFromReply(reply);
    test:assertTrue(taskId is string, "expected a real task id to cancel: " + reply);
    if taskId is string {
        string cancelResult = check cancelAgentTask("PeopleOperations", taskId);
        test:assertTrue(cancelResult.startsWith("[TASK_STATE_CANCELED]"),
                "expected a real CANCELED state after cancelling mid-flight: " + cancelResult);
    }
}

@test:Config {enable: hasRealKey}
function testHardwareProvisioningStartsAsBackgroundTask() returns error? {
    string employeeName = uniqueTestEmployeeName();
    string reply = check delegateToAgent("DigiOps",
            "I need a new standing desk converter, my name is " + employeeName);
    test:assertFalse(reply.startsWith("[TASK_STATE_COMPLETED]"),
            "provisioning takes real minutes after the real ticket is created -- it should not complete within the 20s poll window: "
            + reply);
    string? taskId = extractTaskIdFromReply(reply);
    test:assertTrue(taskId is string, "expected a real task id in the still-in-progress reply: " + reply);
}

@test:Config {enable: hasRealKey}
function testCancelHardwareProvisioningMidFlight() returns error? {
    string employeeName = uniqueTestEmployeeName();
    string reply = check delegateToAgent("DigiOps",
            "I need a new standing desk converter, my name is " + employeeName);
    string? taskId = extractTaskIdFromReply(reply);
    test:assertTrue(taskId is string, "expected a real task id to cancel: " + reply);
    if taskId is string {
        string cancelResult = check cancelAgentTask("DigiOps", taskId);
        test:assertTrue(cancelResult.startsWith("[TASK_STATE_CANCELED]"),
                "expected a real CANCELED state after cancelling mid-flight: " + cancelResult);
    }
}

@test:Config {enable: hasRealKey}
function testParkingReservationTaskCompletes() returns error? {
    // Parking's own reservation delay is a real, short, non-configurable
    // 4s (parking/agent_executor.py) -- comfortably inside the 20s poll
    // window, so this exercises the actual Task/cancel/complete path
    // (unlike testDelegateToParking's availability query, which stays in
    // Message-mode and never creates a Task at all).
    string employeeName = uniqueTestEmployeeName();
    string reply = check delegateToAgent("Parking",
            "reserve spot A04 for " + employeeName);
    test:assertTrue(reply.startsWith("[TASK_STATE_COMPLETED]") || reply.startsWith("[TASK_STATE_REJECTED]"),
            "expected the reservation task to genuinely settle within the poll window: " + reply);
}

@test:Config {enable: hasRealKey}
function testDigiOpsStandardCatalogRequestResolvesFast() returns error? {
    // A standard-catalog item (laptop, monitor, docking station, headset)
    // skips the staged manager-approval wait entirely and resolves fast --
    // the counterpart to testHardwareProvisioningStartsAsBackgroundTask's
    // over-catalog item, which genuinely stays open past the poll window.
    string employeeName = uniqueTestEmployeeName();
    string reply = check delegateToAgent("DigiOps",
            "I need a new docking station, my name is " + employeeName);
    test:assertTrue(reply.startsWith("[TASK_STATE_COMPLETED]"),
            "expected a standard-catalog request to settle fast, within the poll window: " + reply);
}
