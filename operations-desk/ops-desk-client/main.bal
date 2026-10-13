import ballerina/a2a;
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/uuid;

configurable string deskUrl = "http://localhost:9090";

public function main() returns error? {
    a2a:HttpClient desk = check new (deskUrl);

    heading("1. Discover the agent");
    a2a:AgentCard card = check a2a:resolveAgentCard(deskUrl);
    io:println(card.name, " - ", card.description);
    foreach a2a:AgentSkill skill in card.skills {
        io:println("  skill: ", skill.name);
    }
    io:println("  streaming: ", card.capabilities.streaming, ", push notifications: ", card.capabilities.pushNotifications);

    heading("2. Ask for access without saying why");
    a2a:Task paused = check send(desk, {
        message: userMessage("Give Nimal access to the staging cloud project")
    });
    show(paused);

    heading("3. Answer on the same task");
    a2a:Task finished = check send(desk, {
        message: userMessage("It is for the load test of the payments release", paused)
    });
    show(finished);

    heading("4. Stream an incident summary");
    stream<a2a:StreamResponse, a2a:Error?> events = check desk->sendStreamingMessage({
        message: userMessage("What happened to the gateway overnight?")
    });
    check from a2a:StreamResponse event in events
        do {
            io:println("  ", describe(event));
        };

    heading("5. Look the work up again");
    a2a:Task fetched = check desk->getTask({id: finished.id});
    io:println(fetched.id, " is ", fetched.status.state);
    a2a:ListTasksResponse all = check desk->listTasks({});
    foreach a2a:Task task in all.tasks {
        io:println("  ", task.id, "  ", task.status.state);
    }

    heading("6. Cancel a task that is still running");
    a2a:Task started = check send(desk, {
        message: userMessage("Give Kasun access to the vpn. The reason is that he joins the on-call rotation on Monday"),
        configuration: {returnImmediately: true}
    });
    io:println(started.id, " is ", started.status.state);
    runtime:sleep(2);
    a2a:Task running = check desk->getTask({id: started.id});
    io:println(running.id, " is ", running.status.state);
    a2a:Task canceled = check desk->cancelTask({id: started.id});
    io:println(canceled.id, " is ", canceled.status.state);
}

function userMessage(string text, a2a:Task? continuing = ()) returns a2a:Message {
    a2a:Message message = {messageId: uuid:createRandomUuid(), role: a2a:ROLE_USER, parts: [{text}]};
    if continuing is a2a:Task {
        message.taskId = continuing.id;
        message.contextId = continuing.contextId;
    }
    return message;
}

function send(a2a:HttpClient desk, a2a:SendMessageRequest request) returns a2a:Task|error {
    a2a:Task|a2a:Message reply = check desk->sendMessage(request);
    if reply is a2a:Task {
        return reply;
    }
    return error("Expected a task but the agent answered with a message");
}

function show(a2a:Task task) {
    io:println(task.id, " is ", task.status.state);
    a2a:Message? note = task.status.message;
    if note is a2a:Message {
        io:println("  agent: ", textOf(note.parts));
    }
    foreach a2a:Artifact artifact in task.artifacts ?: [] {
        io:println("  artifact: ", textOf(artifact.parts));
    }
}

function describe(a2a:StreamResponse event) returns string {
    if event is a2a:TaskStatusUpdateEvent {
        return "status   " + event.status.state.toString();
    }
    if event is a2a:TaskArtifactUpdateEvent {
        return "artifact " + textOf(event.artifact.parts);
    }
    if event is a2a:Task {
        return "task     " + event.status.state.toString();
    }
    return "message";
}

function textOf(a2a:Part[] parts) returns string {
    string text = "";
    foreach a2a:Part part in parts {
        text += part.text ?: "";
    }
    return text;
}

function heading(string title) {
    io:println("\n== ", title);
}
