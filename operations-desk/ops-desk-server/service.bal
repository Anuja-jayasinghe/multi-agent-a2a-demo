import ballerina/a2a;
import ballerina/http;

final a2a:DefaultHandler handler = new (new OperationsDesk());

final http:Listener deskHttp = check new (9090);
listener a2a:RestListener deskRest = new (deskHttp);
listener a2a:JsonRpcListener deskRpc = new (deskHttp);

@a2a:ServiceConfig {
    agentCard: {
        name: "WSO2 Operations Desk",
        description: "Handles internal operations requests: system access, expense claims, incident summaries and intern onboarding",
        version: "1.0.0",
        provider: {organization: "WSO2", url: "https://wso2.com"},
        skills: [
            {id: "access", name: "Access requests", description: "Grants access to internal systems", tags: ["it", "access"],
                examples: ["Give Nimal access to the staging cloud project"]},
            {id: "expenses", name: "Expense claims", description: "Reviews a claim against policy", tags: ["finance"],
                examples: ["Claim 340 USD for conference travel"]},
            {id: "incidents", name: "Incident summaries", description: "Summarises last night's incidents for a service", tags: ["operations"],
                examples: ["What happened to the gateway overnight?"]},
            {id: "onboarding", name: "Intern onboarding", description: "Builds a first-week checklist", tags: ["people"],
                examples: ["Checklist for Kasun, joining the API Manager team on Monday"]}
        ],
        defaultInputModes: ["text"],
        defaultOutputModes: ["text"],
        capabilities: {},
        supportedInterfaces: []
    }
}
isolated service on deskRest {

    isolated resource function post message\:send(a2a:Context context, a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return handler.handleSendMessage(context, request);
    }

    isolated resource function post message\:stream(a2a:Context context, a2a:SendMessageRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return handler.handleSendStreamingMessage(context, request);
    }

    isolated resource function get tasks/[string id]/subscribe(a2a:Context context, a2a:SubscribeToTaskRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return handler.handleSubscribeToTask(context, request);
    }

    isolated resource function get tasks/[string id](a2a:Context context, a2a:GetTaskRequest request)
            returns a2a:Task|a2a:Error {
        return handler.handleGetTask(context, request);
    }

    isolated resource function get tasks(a2a:Context context, a2a:ListTasksRequest request)
            returns a2a:ListTasksResponse|a2a:Error {
        return handler.handleListTasks(context, request);
    }

    isolated resource function post tasks/[string id]/cancel(a2a:Context context, a2a:CancelTaskRequest request)
            returns a2a:Task|a2a:Error {
        return handler.handleCancelTask(context, request);
    }
}

@a2a:ServiceConfig {
    agentCard: {
        name: "WSO2 Operations Desk",
        description: "Handles internal operations requests: system access, expense claims, incident summaries and intern onboarding",
        version: "1.0.0",
        provider: {organization: "WSO2", url: "https://wso2.com"},
        skills: [
            {id: "access", name: "Access requests", description: "Grants access to internal systems", tags: ["it", "access"],
                examples: ["Give Nimal access to the staging cloud project"]},
            {id: "expenses", name: "Expense claims", description: "Reviews a claim against policy", tags: ["finance"],
                examples: ["Claim 340 USD for conference travel"]},
            {id: "incidents", name: "Incident summaries", description: "Summarises last night's incidents for a service", tags: ["operations"],
                examples: ["What happened to the gateway overnight?"]},
            {id: "onboarding", name: "Intern onboarding", description: "Builds a first-week checklist", tags: ["people"],
                examples: ["Checklist for Kasun, joining the API Manager team on Monday"]}
        ],
        defaultInputModes: ["text"],
        defaultOutputModes: ["text"],
        capabilities: {},
        supportedInterfaces: []
    }
}
isolated service on deskRpc {

    isolated remote function sendMessage(a2a:Context context, a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return handler.handleSendMessage(context, request);
    }

    isolated remote function sendStreamingMessage(a2a:Context context, a2a:SendMessageRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return handler.handleSendStreamingMessage(context, request);
    }

    isolated remote function subscribeToTask(a2a:Context context, a2a:SubscribeToTaskRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return handler.handleSubscribeToTask(context, request);
    }

    isolated remote function getTask(a2a:Context context, a2a:GetTaskRequest request)
            returns a2a:Task|a2a:Error {
        return handler.handleGetTask(context, request);
    }

    isolated remote function listTasks(a2a:Context context, a2a:ListTasksRequest request)
            returns a2a:ListTasksResponse|a2a:Error {
        return handler.handleListTasks(context, request);
    }

    isolated remote function cancelTask(a2a:Context context, a2a:CancelTaskRequest request)
            returns a2a:Task|a2a:Error {
        return handler.handleCancelTask(context, request);
    }
}
