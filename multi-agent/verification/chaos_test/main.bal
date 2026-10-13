// Phase 10 — negative / chaos testing against the real running system.
//
// Written when Parking was deterministic/no-LLM, so every check here
// could target it for zero Anthropic spend. Parking is now real
// LLM-backed too (see docs/architecture.md's "As built" note) — the
// malformed-request checks below still don't reach an LLM call (they're
// rejected at the transport/parsing layer), but the concurrent-load
// check (20 simultaneous real sendMessage calls) now makes 20 real,
// parallel Anthropic calls per run, no longer free or deterministic.
// Not redesigned here — flagging for a real decision on how Phase 10's
// chaos testing should work now that no downstream agent is LLM-free.
// Real running processes throughout, nothing mocked.
//
// Start Parking and Payroll first (scripts/start-all.sh, or just those
// two individually), then run this script once: bal run --sticky
import ballerina/a2a;
import ballerina/http;
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/uuid;

const string PARKING_URL = "http://127.0.0.1:8000";
const string PAYROLL_URL = "http://127.0.0.1:8003";

function mkMessage(string text) returns a2a:Message => {
    messageId: uuid:createType4AsString(),
    role: a2a:ROLE_USER,
    parts: [{text}]
};

function isAlive(string agentUrl) returns boolean {
    a2a:AgentCard|error card = a2a:resolveAgentCard(agentUrl);
    return card is a2a:AgentCard;
}

public function main() returns error? {
    int failures = 0;
    io:println("=== Phase 10 — negative / chaos testing (concurrent-load check now spends real Anthropic calls against Parking — see file header) ===\n");

    // --- 1. Malformed requests: REST binding (Parking) ---
    http:Client rawParking = check new (PARKING_URL);

    http:Response|error badJson = rawParking->post("/message:send", "{not valid json",
            {"Content-Type": "application/json", "A2A-Version": "1.0"});
    if badJson is http:Response && badJson.statusCode >= 400 && badJson.statusCode < 500 {
        io:println("[ok] malformed JSON body rejected with HTTP ", badJson.statusCode);
    } else {
        io:println("[FAIL] malformed JSON body was not rejected as expected");
        failures += 1;
    }

    http:Response|error missingParts = rawParking->post("/message:send",
            {"message": {"messageId": uuid:createType4AsString(), "role": "user"}},
            {"Content-Type": "application/json", "A2A-Version": "1.0"});
    if missingParts is http:Response && missingParts.statusCode >= 400 && missingParts.statusCode < 500 {
        io:println("[ok] message missing required 'parts' field rejected with HTTP ", missingParts.statusCode);
    } else {
        io:println("[FAIL] message missing 'parts' was not rejected as expected");
        failures += 1;
    }

    if isAlive(PARKING_URL) {
        io:println("[ok] Parking still alive and serving its card after malformed requests\n");
    } else {
        io:println("[FAIL] Parking did not survive the malformed-request battery\n");
        failures += 1;
    }

    // --- 2. Malformed requests: JSON-RPC binding (DigiOps) ---
    http:Client rawDigiOps = check new ("http://127.0.0.1:8001");

    http:Response|error notJsonRpc = rawDigiOps->post("/", {"foo": "bar"},
            {"Content-Type": "application/json", "A2A-Version": "1.0"});
    boolean rpcRejected = false;
    if notJsonRpc is http:Response {
        json|error body = notJsonRpc.getJsonPayload();
        rpcRejected = notJsonRpc.statusCode >= 400 || body is map<json> && body.hasKey("error");
    }
    if rpcRejected {
        io:println("[ok] non-JSON-RPC body rejected");
    } else {
        io:println("[FAIL] non-JSON-RPC body was not rejected as expected");
        failures += 1;
    }

    http:Response|error badMethod = rawDigiOps->post("/",
            {"jsonrpc": "2.0", "id": 1, "method": "totally/not/a/real/method", "params": {}},
            {"Content-Type": "application/json", "A2A-Version": "1.0"});
    boolean methodRejected = false;
    if badMethod is http:Response {
        json|error body = badMethod.getJsonPayload();
        methodRejected = body is map<json> && body.hasKey("error");
    }
    if methodRejected {
        io:println("[ok] unknown JSON-RPC method rejected with a real JSON-RPC error");
    } else {
        io:println("[FAIL] unknown JSON-RPC method was not rejected as expected");
        failures += 1;
    }

    if isAlive("http://127.0.0.1:8001") {
        io:println("[ok] DigiOps still alive and serving its card after malformed requests\n");
    } else {
        io:println("[FAIL] DigiOps did not survive the malformed-request battery\n");
        failures += 1;
    }

    // --- 3. Input validation: gRPC binding (Payroll), pure data ops ---
    a2a:AgentCard payrollCard = check a2a:resolveAgentCard(PAYROLL_URL);
    a2a:GrpcClient payroll = check new (payrollCard);

    a2a:TaskPushNotificationConfig|error badConfig = payroll->createTaskPushNotificationConfig({
        url: "not a valid url at all",
        taskId: "also-not-a-real-task"
    });
    if badConfig is error {
        io:println("[ok] push-notification config with an invalid task/URL rejected gracefully: ", badConfig.message());
    } else {
        io:println("[FAIL] invalid push-notification config was unexpectedly accepted");
        failures += 1;
    }

    if isAlive(PAYROLL_URL) {
        io:println("[ok] Payroll still alive and serving its card after invalid input\n");
    } else {
        io:println("[FAIL] Payroll did not survive the invalid-input battery\n");
        failures += 1;
    }

    // --- 4. Concurrent load: 20 simultaneous real requests against Parking ---
    a2a:AgentCard parkingCard = check a2a:resolveAgentCard(PARKING_URL);
    a2a:RestClient parking = check new (parkingCard);

    future<a2a:Task|a2a:Message|error>[] loadFutures = [];
    foreach int i in 0 ..< 20 {
        future<a2a:Task|a2a:Message|error> f = start parking->sendMessage({message: mkMessage("is spot A01 available?")});
        loadFutures.push(f);
    }
    int loadOk = 0;
    foreach future<a2a:Task|a2a:Message|error> f in loadFutures {
        a2a:Task|a2a:Message|error r = wait f;
        if r is a2a:Task || r is a2a:Message {
            loadOk += 1;
        }
    }
    io:println("[", loadOk == 20 ? "ok" : "FAIL", "] concurrent load: ", loadOk, "/20 simultaneous requests completed successfully");
    if loadOk != 20 {
        failures += 1;
    }
    if isAlive(PARKING_URL) {
        io:println("[ok] Parking still alive and serving its card after concurrent load\n");
    } else {
        io:println("[FAIL] Parking did not survive the concurrent load\n");
        failures += 1;
    }

    // --- 5. Resource-leak sanity: repeated card resolution + config CRUD cycles ---
    int cardResolveOk = 0;
    foreach int i in 0 ..< 30 {
        a2a:AgentCard|error c = a2a:resolveAgentCard(PARKING_URL);
        if c is a2a:AgentCard {
            cardResolveOk += 1;
        }
    }
    io:println("[", cardResolveOk == 30 ? "ok" : "FAIL", "] repeated agent-card resolution: ", cardResolveOk, "/30 succeeded");
    if cardResolveOk != 30 {
        failures += 1;
    }

    // Fresh client construction + teardown, 30 times in a row — exercises
    // real connection lifecycle repeatedly, not just one long-lived client.
    int freshClientOk = 0;
    foreach int i in 0 ..< 30 {
        a2a:RestClient|error freshClient = new (parkingCard);
        if freshClient is a2a:RestClient {
            a2a:Task|a2a:Message|error r = freshClient->sendMessage({message: mkMessage("is spot A02 available?")});
            if r is a2a:Task || r is a2a:Message {
                freshClientOk += 1;
            }
        }
    }
    io:println("[", freshClientOk == 30 ? "ok" : "FAIL", "] 30 fresh client construct+use+drop cycles: ", freshClientOk, "/30 succeeded");
    if freshClientOk != 30 {
        failures += 1;
    }

    runtime:sleep(1);
    if isAlive(PARKING_URL) && isAlive(PAYROLL_URL) {
        io:println("[ok] both agents still alive and healthy after the full chaos battery\n");
    } else {
        io:println("[FAIL] an agent did not survive the full chaos battery\n");
        failures += 1;
    }

    io:println("=== ", failures == 0 ? "ALL CHAOS CHECKS PASSED — zero panics, zero crashes" : failures.toString() + " FAILURE(S)", " ===");
    if failures > 0 {
        return error(failures.toString() + " chaos check(s) failed");
    }
}
