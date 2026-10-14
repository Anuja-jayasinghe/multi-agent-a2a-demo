import ballerina/ai;
import ballerinax/ai.anthropic;

configurable string anthropicApiKey = ?;

const string ASSISTANT_INSTRUCTIONS = "You help WSO2 staff with internal operations by working with the Operations Desk, " +
    "another agent, through your tools. Send each request to the desk once, and use inBackground when the user wants to keep " +
    "working or may cancel, then check on the task. Stream from the desk when the user wants to watch progress. " +
    "If the desk asks for more detail, ask the user for exactly that and continue the same task with its taskId. " +
    "Report what happened in one or two short sentences.";

final ai:ModelProvider model = check new anthropic:ModelProvider(anthropicApiKey, anthropic:CLAUDE_HAIKU_4_5);

final ai:Agent assistant = check new (
    systemPrompt = {
        role: "WSO2 staff assistant",
        instructions: ASSISTANT_INSTRUCTIONS
    },
    model = model,
    tools = [askOperationsDesk, streamFromOperationsDesk, getDeskTask, listDeskTasks, cancelDeskTask],
    maxIter = 6
);
