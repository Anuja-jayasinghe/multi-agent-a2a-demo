import ballerina/a2a;
import ballerina/http;

type DeskRequest record {|
    string message;
    string taskId = "";
    boolean returnImmediately = false;
|};

service /lifecycle on chatEndpoint {

    resource function get card() returns a2a:AgentCard|error {
        return a2a:resolveAgentCard(deskUrl);
    }

    resource function post send(DeskRequest request) returns a2a:Task|a2a:Message|error {
        a2a:HttpClient desk = check deskClient();
        return desk->sendMessage({
            message: userMessage(request.message, request.taskId),
            configuration: {returnImmediately: request.returnImmediately}
        });
    }

    resource function post 'stream(DeskRequest request) returns stream<http:SseEvent, error?>|error {
        a2a:HttpClient desk = check deskClient();
        stream<a2a:StreamResponse, a2a:Error?> events = check desk->sendStreamingMessage({
            message: userMessage(request.message, request.taskId)
        });
        return stream from a2a:StreamResponse event in events
            select {data: event.toJsonString()};
    }

    resource function get tasks() returns a2a:ListTasksResponse|error {
        a2a:HttpClient desk = check deskClient();
        return desk->listTasks({});
    }

    resource function get tasks/[string id]() returns a2a:Task|http:NotFound|error {
        a2a:HttpClient desk = check deskClient();
        a2a:Task|a2a:Error result = desk->getTask({id});
        return notFoundOr(result);
    }

    resource function post tasks/[string id]/cancel() returns a2a:Task|http:NotFound|error {
        a2a:HttpClient desk = check deskClient();
        a2a:Task|a2a:Error result = desk->cancelTask({id});
        return notFoundOr(result);
    }
}

isolated function notFoundOr(a2a:Task|a2a:Error result) returns a2a:Task|http:NotFound|error {
    if result is a2a:TaskNotFoundError {
        return {body: result.message()};
    }
    return result;
}
