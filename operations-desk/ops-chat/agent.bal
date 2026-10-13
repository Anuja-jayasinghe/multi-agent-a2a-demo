import ballerina/a2a;
import ballerina/ai;
import ballerina/uuid;
import ballerinax/ai.anthropic;

configurable string anthropicApiKey = ?;
configurable string deskUrl = "http://localhost:9090";

type DeskAnswer record {|
    string taskId;
    string state;
    string text;
|};

isolated a2a:HttpClient? cachedDesk = ();

# Sends a request to the WSO2 Operations Desk agent: system access, expense claims, incident summaries and
# intern onboarding. When the answer's state is TASK_STATE_INPUT_REQUIRED the desk needs more detail: ask the
# user, then call this tool again with the same taskId and their answer.
#
# + request - What the user wants, or their answer to the desk's question
# + taskId - The taskId returned earlier when the desk asked for more detail; empty for a new request
# + return - The desk's answer with its taskId and state, or an error
@ai:AgentTool
isolated function askOperationsDesk(string request, string taskId = "") returns DeskAnswer|error {
    a2a:Message message = {messageId: uuid:createRandomUuid(), role: a2a:ROLE_USER, parts: [{text: request}]};
    if taskId != "" {
        message.taskId = taskId;
    }
    a2a:HttpClient desk = check deskClient();
    a2a:Task|a2a:Message reply = check desk->sendMessage({message});
    if reply is a2a:Task {
        string text = "";
        a2a:Message? note = reply.status.message;
        if note is a2a:Message {
            text = textOf(note.parts);
        }
        foreach a2a:Artifact artifact in reply.artifacts ?: [] {
            text += textOf(artifact.parts);
        }
        return {taskId: reply.id, state: reply.status.state.toString(), text};
    }
    return {taskId, state: "TASK_STATE_COMPLETED", text: textOf((<a2a:Message>reply).parts)};
}

isolated function deskClient() returns a2a:HttpClient|error {
    lock {
        a2a:HttpClient? existing = cachedDesk;
        if existing is a2a:HttpClient {
            return existing;
        }
        a2a:HttpClient created = check new (deskUrl);
        cachedDesk = created;
        return created;
    }
}

isolated function textOf(a2a:Part[] parts) returns string {
    string text = "";
    foreach a2a:Part part in parts {
        text += part.text ?: "";
    }
    return text;
}

final ai:ModelProvider model = check new anthropic:ModelProvider(anthropicApiKey, anthropic:CLAUDE_HAIKU_4_5);

final ai:Agent assistant = check new (
    systemPrompt = {
        role: "WSO2 staff assistant",
        instructions: "Help WSO2 staff with internal operations by delegating to the Operations Desk with the " +
            "askOperationsDesk tool. If the desk asks for more detail, ask the user for exactly that and then " +
            "call the tool again with the same taskId. Report what the desk did in one or two short sentences."
    },
    model = model,
    tools = [askOperationsDesk],
    maxIter = 6
);
