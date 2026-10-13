// Phase 12 — confirms the containerized system behaves the same as the
// local-process one. Unlike every other verification/ script, this one
// must run *inside* the Docker Compose network (docker-compose service
// names like "parking" only resolve there, not from the host) — see
// scripts/docker-verify.sh, which builds this and runs it in a
// throwaway container attached to the compose network.
//
// No Anthropic key needed or spent: card resolution for all five real
// containerized agents, plus one real sendMessage round-trip against
// Parking (fully deterministic, no LLM) to confirm actual RPC — not
// just discovery — genuinely works over the Docker network, the same
// way it does locally.
import ballerina/a2a;
import ballerina/http;
import ballerina/io;
import ballerina/uuid;

public function main() returns error? {
    int failures = 0;
    io:println("=== Docker Compose parity check ===\n");

    string[] names = ["parking", "digiops", "peopleoperations", "payroll", "travel_expense"];
    int[] ports = [8000, 8001, 8002, 8003, 8004];
    foreach int i in 0 ..< names.length() {
        string url = "http://" + names[i] + ":" + ports[i].toString();
        a2a:AgentCard|error card = a2a:resolveAgentCard(url);
        if card is a2a:AgentCard {
            io:println("[ok] ", names[i], " card resolved over Docker DNS: ", card.name);
        } else {
            io:println("[FAIL] ", names[i], " card resolution failed: ", card.message());
            failures += 1;
        }
    }

    http:Client webhookReceiver = check new ("http://orchestrator:9090");
    http:Response|error received = webhookReceiver->get("/webhooks/received");
    if received is http:Response && received.statusCode == 200 {
        io:println("[ok] orchestrator webhook receiver reachable over Docker DNS");
    } else {
        io:println("[FAIL] orchestrator webhook receiver not reachable");
        failures += 1;
    }

    a2a:AgentCard parkingCard = check a2a:resolveAgentCard("http://parking:8000");
    a2a:RestClient parking = check new (parkingCard);
    a2a:Message msg = {messageId: uuid:createType4AsString(), role: a2a:ROLE_USER, parts: [{text: "is spot A01 available?"}]};
    a2a:Task|a2a:Message|error result = parking->sendMessage({message: msg});
    if result is error {
        io:println("[FAIL] sendMessage against containerized Parking failed: ", result.message());
        failures += 1;
    } else {
        io:println("[ok] real sendMessage round-trip against containerized Parking succeeded");
    }

    io:println("\n=== ", failures == 0 ? "DOCKER COMPOSE PARITY CONFIRMED" : failures.toString() + " FAILURE(S)", " ===");
    if failures > 0 {
        return error(failures.toString() + " parity check(s) failed");
    }
}
