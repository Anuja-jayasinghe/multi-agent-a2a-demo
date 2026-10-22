import ballerina/a2a;
import ballerina/ai;
import ballerina/uuid;

configurable string deskUrl = "http://localhost:9090";

final a2a:RestClient desk = check new (deskUrl);

type DeskTask record {|
    string taskId;
    string state;
    string text;
|};

# Sends a request to the Operations Desk: access requests, expense claims, incident summaries, intern onboarding.
# If the state is TASK_STATE_INPUT_REQUIRED, ask the user for the missing detail and call again with the same taskId.
#
# + request - What the user wants, or their answer to the desk's question
# + taskId - The task to continue; empty for a new request
# + inBackground - Return at once while the task keeps running
# + return - The task id, its state and the desk's words
@ai:AgentTool
isolated function askOperationsDesk(string request, string taskId = "", boolean inBackground = false)
        returns DeskTask|error {
    a2a:Task|a2a:Message reply = check desk->sendMessage({
        message: userMessage(request, taskId),
        configuration: {returnImmediately: inBackground}
    });
    if reply is a2a:Task {
        return deskTask(reply);
    }
    return {taskId, state: "TASK_STATE_COMPLETED", text: textOf((<a2a:Message>reply).parts)};
}

# Sends a request to the Operations Desk and returns every update it streams back.
#
# + request - What the user wants
# + return - The updates in the order they arrived
@ai:AgentTool
isolated function streamFromOperationsDesk(string request) returns string[]|error {
    stream<a2a:StreamResponse, a2a:Error?> events = check desk->sendStreamingMessage({
        message: userMessage(request)
    });
    return from a2a:StreamResponse event in events
        select describeEvent(event);
}

# Looks up one task on the Operations Desk.
#
# + taskId - The task's id
# + return - The task's state and the desk's words
@ai:AgentTool
isolated function getDeskTask(string taskId) returns DeskTask|error {
    a2a:Task task = check desk->getTask({id: taskId});
    return deskTask(task);
}

# Lists the tasks on the Operations Desk.
#
# + return - The tasks with their states
@ai:AgentTool
isolated function listDeskTasks() returns DeskTask[]|error {
    a2a:ListTasksResponse response = check desk->listTasks({});
    return from a2a:Task task in response.tasks
        select deskTask(task);
}

# Cancels a task that is still running on the Operations Desk.
#
# + taskId - The task's id
# + return - The task with its new state
@ai:AgentTool
isolated function cancelDeskTask(string taskId) returns DeskTask|error {
    a2a:Task task = check desk->cancelTask({id: taskId});
    return deskTask(task);
}

isolated function userMessage(string text, string taskId = "") returns a2a:Message {
    a2a:Message message = {messageId: uuid:createRandomUuid(), role: a2a:ROLE_USER, parts: [{text}]};
    if taskId != "" {
        message.taskId = taskId;
    }
    return message;
}

isolated function deskTask(a2a:Task task) returns DeskTask {
    string text = "";
    a2a:Message? note = task.status.message;
    if note is a2a:Message {
        text = textOf(note.parts);
    }
    foreach a2a:Artifact artifact in task.artifacts ?: [] {
        text += textOf(artifact.parts);
    }
    return {taskId: task.id, state: task.status.state.toString(), text};
}

isolated function describeEvent(a2a:StreamResponse event) returns string {
    if event is a2a:TaskStatusUpdateEvent {
        return "status " + event.status.state.toString();
    }
    if event is a2a:TaskArtifactUpdateEvent {
        return "artifact " + textOf(event.artifact.parts);
    }
    if event is a2a:Task {
        return "task " + event.status.state.toString();
    }
    return "message";
}

isolated function textOf(a2a:Part[] parts) returns string {
    string text = "";
    foreach a2a:Part part in parts {
        text += part.text ?: "";
    }
    return text;
}
