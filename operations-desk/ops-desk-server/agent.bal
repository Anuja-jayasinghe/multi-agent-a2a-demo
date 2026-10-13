import ballerina/a2a;
import ballerina/ai;
import ballerina/uuid;
import ballerinax/ai.anthropic;

configurable string anthropicApiKey = ?;

type DeskReply record {|
    "completed"|"input_required" status;
    string message;
|};

const string DESK_INSTRUCTIONS = "You help WSO2 staff with internal operations: access requests, expense claims, " +
    "incident summaries and intern onboarding. Use the tools for every answer and never invent data. " +
    "Answer in two or three short sentences, except for a checklist or an incident list. " +
    "If a detail you need is missing, such as the business justification for an access request or the receipt " +
    "for a claim, set status to input_required and ask for exactly that. Otherwise set status to completed.";

final ai:ModelProvider model = check new anthropic:ModelProvider(anthropicApiKey, anthropic:CLAUDE_HAIKU_4_5);

final ai:Agent deskAgent = check new (
    systemPrompt = {
        role: "WSO2 Operations Desk",
        instructions: DESK_INSTRUCTIONS
    },
    model = model,
    tools = [requestAccess, submitExpenseClaim, getIncidentSummary, getOnboardingChecklist],
    maxIter = 6
);

isolated class OperationsDesk {
    *a2a:AgentExecutor;

    public isolated function execute(a2a:RequestContext context, a2a:TaskUpdater updater)
            returns a2a:Message|a2a:Error? {
        check updater->working();
        DeskReply|ai:Error reply = deskAgent.run(textOf(context.message), sessionId = updater.getContextId());
        if reply is ai:Error {
            check updater->failed(agentMessage(reply.message()));
            return;
        }
        if reply.status == "input_required" {
            check updater->requireInput(agentMessage(reply.message));
            return;
        }
        check updater->addArtifact([{text: reply.message}], name = "answer");
        check updater->complete();
        return;
    }
}

isolated function textOf(a2a:Message message) returns string {
    string text = "";
    foreach a2a:Part part in message.parts {
        text += part.text ?: "";
    }
    return text;
}

isolated function agentMessage(string text) returns a2a:Message => {
    messageId: uuid:createRandomUuid(),
    role: a2a:ROLE_AGENT,
    parts: [{text}]
};
