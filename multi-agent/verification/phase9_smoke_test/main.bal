// Phase 9 functional smoke test — real Anthropic calls against the real
// running agents. Scenarios 1-6 from docs/DEMO_SCRIPT.md (direct-to-agent);
// orchestrator routing scenarios 7-10 live in
// orchestrator/tests/phase9_routing_test.bal, since the concierge Agent
// has no network-facing interface of its own to call from here.
//
// Start all five agents first (scripts/start-all.sh with a real
// ANTHROPIC_API_KEY in .env), then run this script once from this
// directory: bal run --sticky
import ballerina/a2a;
import ballerina/io;
import ballerina/uuid;

function mkMessage(string text) returns a2a:Message => {
    messageId: uuid:createType4AsString(),
    role: a2a:ROLE_USER,
    parts: [{text}]
};

function joinParts(a2a:Part[] parts) returns string {
    string[] texts = [];
    foreach a2a:Part p in parts {
        string? t = p?.text;
        if t is string {
            texts.push(t);
        }
    }
    return string:'join(" ", ...texts);
}

function extractText(a2a:Task|a2a:Message result) returns string {
    if result is a2a:Message {
        return joinParts(result.parts);
    } else if result is a2a:Task {
        a2a:Task task = result;
        a2a:Artifact[] artifacts = task.artifacts ?: [];
        if artifacts.length() > 0 {
            return joinParts(artifacts[artifacts.length() - 1].parts);
        }
        a2a:Message? statusMessage = task.status?.message;
        if statusMessage is a2a:Message {
            return joinParts(statusMessage.parts);
        }
        return "(no text — state: " + task.status.state.toString() + ")";
    }
    panic error("unreachable: result is always a2a:Task or a2a:Message");
}

type StreamOutcome record {|
    string? finalState;
    string collectedText;
|};

function consumeStream(stream<a2a:StreamResponse, error?> s) returns StreamOutcome|error {
    string? finalState = ();
    string[] chunks = [];
    while true {
        record {|a2a:StreamResponse value;|}|error? item = s.next();
        if item is () {
            break;
        }
        if item is error {
            check s.close();
            return item;
        }
        a2a:StreamResponse sr = item.value;
        if sr is a2a:TaskStatusUpdateEvent {
            finalState = sr.status.state.toString();
            a2a:Message? m = sr.status.message;
            if m is a2a:Message {
                chunks.push(joinParts(m.parts));
            }
        }
        if sr is a2a:TaskArtifactUpdateEvent {
            chunks.push(joinParts(sr.artifact.parts));
        }
        if sr is a2a:Message {
            chunks.push(joinParts(sr.parts));
        }
    }
    check s.close();
    return {finalState, collectedText: string:'join(" ", ...chunks)};
}

public function main() returns error? {
    io:println("=== Phase 9 functional smoke test — real Anthropic calls ===\n");

    // 1. DigiOps FAQ
    a2a:Client digiops = check new ("http://127.0.0.1:8001");
    a2a:Task|a2a:Message faq = check digiops->sendMessage({message: mkMessage("what's the password policy?")});
    io:println("[1] DigiOps FAQ:\n", extractText(faq), "\n");

    // 2. DigiOps incident (streaming)
    stream<a2a:StreamResponse, error?> incidentStream = check digiops->sendStreamingMessage(
        {message: mkMessage("I can't reach the internal wiki, is there an outage?")} );
    StreamOutcome incidentOutcome = check consumeStream(incidentStream);
    io:println("[2] DigiOps incident — final state: ", incidentOutcome.finalState ?: "?",
            "\n", incidentOutcome.collectedText, "\n");

    // 3. PeopleOperations FAQ
    a2a:Client peopleOps = check new ("http://127.0.0.1:8002");
    a2a:Task|a2a:Message hrFaq = check peopleOps->sendMessage({message: mkMessage("how many annual leave days do I get?")});
    io:println("[3] PeopleOperations FAQ:\n", extractText(hrFaq), "\n");

    // 4. PeopleOperations onboarding (streaming, real tool calls)
    stream<a2a:StreamResponse, error?> onboardingStream = check peopleOps->sendStreamingMessage(
        {message: mkMessage("please start onboarding for a new hire named Nadeesha Perera")});
    StreamOutcome onboardingOutcome = check consumeStream(onboardingStream);
    io:println("[4] PeopleOperations onboarding — final state: ", onboardingOutcome.finalState ?: "?",
            "\n", onboardingOutcome.collectedText, "\n");

    // 5. Payroll payslip correction (gRPC, real tool call)
    a2a:Client payroll = check new ("http://127.0.0.1:8003");
    a2a:Task|a2a:Message correction = check payroll->sendMessage(
        {message: mkMessage("my payslip shows the wrong tax deduction, please file a correction")});
    io:println("[5] Payroll correction:\n", extractText(correction), "\n");

    // 6. Travel & Expense claim (REST, real tool call)
    a2a:Client travel = check new ("http://127.0.0.1:8004");
    a2a:Task|a2a:Message claim = check travel->sendMessage(
        {message: mkMessage("I need to claim LKR 8000 for a client dinner in Colombo")});
    io:println("[6] Travel & Expense claim:\n", extractText(claim), "\n");

    io:println("=== smoke test complete — see docs/DEMO_SCRIPT.md for RESULT annotations ===");
}
