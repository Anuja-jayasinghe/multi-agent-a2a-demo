// Real ballerina/a2a GrpcClient verification against the real, running
// Payroll Agent (agents/payroll) — no mocks, no stubs.
//
// Start the agent first (the admin token only matters for the
// extended-card check, which needs no LLM either):
//
//   cd agents/payroll
//   PAYROLL_ADMIN_TOKEN=demo-payroll-admin-secret \
//     java -jar target/quarkus-app/quarkus-run.jar
//
// then run this script from this directory: bal run --sticky
//
// Card resolution, task-lifecycle round-tripping, push-notification CRUD,
// and extended-card gating all pass today, no key needed. The one check
// that needs the model to actually answer (sendMessage's response
// content) is marked DEFERRED and re-run for real in Phase 9.
import ballerina/a2a;
import ballerina/io;
import ballerina/os;
import ballerina/uuid;

const string AGENT_URL = "http://127.0.0.1:8003";

// From the same env var the agent reads — see the note in
// verification/peopleoperations/main.bal for why this is not a constant.
final string ADMIN_TOKEN = os:getEnv("PAYROLL_ADMIN_TOKEN") != ""
    ? os:getEnv("PAYROLL_ADMIN_TOKEN")
    : "demo-payroll-admin-secret";

public function main() returns error? {
    int failures = 0;
    io:println("=== Payroll Agent — real ballerina/a2a GrpcClient verification ===\n");

    // 1. Agent card resolves correctly, gRPC-only.
    a2a:AgentCard card = check a2a:resolveAgentCard(AGENT_URL);
    boolean grpcOnly = card.supportedInterfaces.length() == 1
            && card.supportedInterfaces[0].protocolBinding == "GRPC";
    if card.name == "Payroll Agent" && card.capabilities.pushNotifications
            && card.capabilities.extendedAgentCard && grpcOnly {
        io:println("[ok] agent card resolves correctly, gRPC-only, pushNotifications + extendedAgentCard declared");
    } else {
        io:println("[FAIL] unexpected agent card content");
        failures += 1;
    }

    a2a:GrpcClient agent = check new (card);

    // 2. sendMessage without a real key must fail gracefully — proving the
    // whole langchain4j -> A2A -> gRPC -> ballerina/a2a pipeline is wired
    // end to end. [DEFERRED to Phase 9 for the actual answer.] The task IS
    // genuinely created before the LLM call fails (submit -> startWork
    // happen first), and its real ID is named in the error — captured
    // below to drive the push-notification CRUD checks against a real task.
    a2a:Message msg = {messageId: uuid:createType4AsString(), role: a2a:ROLE_USER, parts: [{text: "my payslip shows the wrong tax deduction"}]};
    a2a:Task|a2a:Message|error sendResult = agent->sendMessage(msg);
    string? taskId = ();
    if sendResult is error {
        io:println("[ok] sendMessage fails gracefully without a real key: ", sendResult.message());
        foreach string token in re `\s+`.split(sendResult.message()) {
            if token.length() == 36 && token.includes("-") {
                taskId = token;
            }
        }
    } else if sendResult is a2a:Task {
        io:println("[ok] sendMessage succeeded with a real key — real task id: ", sendResult.id);
        taskId = sendResult.id;
    } else {
        io:println("[FAIL] sendMessage returned a bare Message — expected a Task either way");
    }
    if taskId is () {
        io:println("[FAIL] could not recover a real task ID to drive the remaining checks");
        failures += 1;
        return error(failures.toString() + " verification check(s) failed");
    }
    string realTaskId = taskId;

    // 3. getTask/cancelTask genuinely round-trip over gRPC.
    a2a:Task|error getResult = agent->getTask(realTaskId);
    if getResult is a2a:Task {
        io:println("[ok] getTask resolves the real task, state: ", getResult.status.state);
    } else {
        io:println("[FAIL] getTask on a real task ID failed: ", getResult.message());
        failures += 1;
    }

    a2a:Task|error cancelOnMissing = agent->cancelTask("nonexistent-task-id");
    if cancelOnMissing is error {
        io:println("[ok] cancelTask on a nonexistent task fails gracefully: ", cancelOnMissing.message());
    } else {
        io:println("[FAIL] cancelTask on a nonexistent task unexpectedly succeeded");
        failures += 1;
    }

    // 4. Push-notification config CRUD — pure data, no LLM, fully verified
    // now, against the real task created above.
    a2a:TaskPushNotificationConfig created = check agent->createTaskPushNotificationConfig({
        url: "http://127.0.0.1:9999/webhook",
        taskId: realTaskId
    });
    string configId = created?.id ?: "";
    a2a:TaskPushNotificationConfig fetched = check agent->getTaskPushNotificationConfig(realTaskId, configId);
    a2a:ListTaskPushNotificationConfigsResult listed = check agent->listTaskPushNotificationConfigs(realTaskId);
    check agent->deleteTaskPushNotificationConfig(realTaskId, configId);
    a2a:TaskPushNotificationConfig|error afterDelete = agent->getTaskPushNotificationConfig(realTaskId, configId);
    if fetched.url == created.url && listed.configs.length() == 1 && afterDelete is error {
        io:println("[ok] push-notification config CRUD round-trips for real: create, get, list, delete all confirmed");
    } else {
        io:println("[FAIL] push-notification config CRUD did not behave as expected");
        failures += 1;
    }

    // 5. Extended agent card is admin-gated — a real bearer-token check
    // enforced by a gRPC interceptor scoped to only this RPC (see
    // AdminOnlyExtendedCardInterceptor). Rejects outright rather than
    // downgrading, since this SDK version's gRPC binding has no per-caller
    // card-modifier hook — a different, still-genuine answer than
    // PeopleOperations's downgrade approach.
    a2a:AgentCard|error unauthResult = agent->getExtendedAgentCard();
    a2a:GrpcClient authed = check new (card, headers = {"Authorization": "Bearer " + ADMIN_TOKEN});
    a2a:AgentCard authedCard = check authed->getExtendedAgentCard();
    boolean hasAdminSkill = authedCard.skills.some(s => s.id == "adjust-other-employee-payroll");
    if unauthResult is error && hasAdminSkill {
        io:println("[ok] extended card genuinely gated: unauthenticated rejected, authenticated gets ",
                authedCard.skills.length(), " skills including the admin-only one");
    } else {
        io:println("[FAIL] extended card gating did not behave as expected");
        failures += 1;
    }

    io:println("\n=== ", failures == 0 ? "ALL STRUCTURAL CHECKS PASSED" : failures.toString() + " FAILURE(S)",
            " (functional check deferred to Phase 9) ===");
    if failures > 0 {
        return error(failures.toString() + " verification check(s) failed");
    }
}
