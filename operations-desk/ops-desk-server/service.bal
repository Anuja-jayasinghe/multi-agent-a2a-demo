import ballerina/a2a;

final a2a:DefaultHandler handler = new (new OperationsDesk());

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
isolated service /rest on new a2a:HttpListener(9090) {

    isolated remote function onSendMessage(a2a:Context context, a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return handler.sendMessage(context, request);
    }

    isolated remote function onSendStreamingMessage(a2a:Context context, a2a:SendMessageRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return handler.sendStreamingMessage(context, request);
    }

    isolated remote function onSubscribeToTask(a2a:Context context, a2a:SubscribeToTaskRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return handler.subscribeToTask(context, request);
    }

    isolated remote function onGetTask(a2a:Context context, a2a:GetTaskRequest request)
            returns a2a:Task|a2a:Error {
        return handler.getTask(context, request);
    }

    isolated remote function onListTasks(a2a:Context context, a2a:ListTasksRequest request)
            returns a2a:ListTasksResponse|a2a:Error {
        return handler.listTasks(context, request);
    }

    isolated remote function onCancelTask(a2a:Context context, a2a:CancelTaskRequest request)
            returns a2a:Task|a2a:Error {
        return handler.cancelTask(context, request);
    }
}
