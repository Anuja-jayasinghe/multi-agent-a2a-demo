import ballerina/a2a;
import ballerina/uuid;

configurable string deskUrl = "http://localhost:9090";

isolated a2a:HttpClient? cachedDesk = ();

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

isolated function userMessage(string text, string taskId = "") returns a2a:Message {
    a2a:Message message = {messageId: uuid:createRandomUuid(), role: a2a:ROLE_USER, parts: [{text}]};
    if taskId != "" {
        message.taskId = taskId;
    }
    return message;
}

isolated function textOf(a2a:Part[] parts) returns string {
    string text = "";
    foreach a2a:Part part in parts {
        text += part.text ?: "";
    }
    return text;
}
