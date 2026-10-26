import ballerina/a2a;

import wso2/a2a_toolkit;

configurable int tripPlannerA2aPort = 9096;
listener a2a:RestListener tripPlannerA2aListener = new (tripPlannerA2aPort);

isolated class TripPlannerA2aExecutor {
    *a2a:AgentExecutor;

    public isolated function execute(a2a:RequestContext context, a2a:TaskUpdater updater)
            returns a2a:Message|a2a:Error? {
        return a2a_toolkit:runAgent(tripPlanner, context, updater);
    }
}

@a2a:ServiceConfig {
    agentCard: {
        name: "Trip Planner Agent",
        description: "Plan a short, one-day itinerary for the city the user names: 3 to 4 activities, each one sentence.",
        version: "1.0.0",
        skills: [
            {
                id: "trip-planner",
                name: "Trip Planner",
                description: "Plan a short, one-day itinerary for the city the user names: 3 to 4 activities, each one sentence.",
                tags: []
            }
        ],
        defaultInputModes: ["text"],
        defaultOutputModes: ["text"],
        capabilities: {},
        supportedInterfaces: []
    }
}
isolated service on tripPlannerA2aListener {

    private final a2a:DefaultHandler handler = new (new TripPlannerA2aExecutor());

    isolated resource function post message\:send(a2a:Context context,
            a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return self.handler.handleSendMessage(context, request);
    }

    isolated resource function post message\:stream(a2a:Context context,
            a2a:SendMessageRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return self.handler.handleSendStreamingMessage(context, request);
    }

    isolated resource function get tasks/[string id]/subscribe(
            a2a:Context context, a2a:SubscribeToTaskRequest request)
            returns stream<a2a:StreamResponse, a2a:Error?>|a2a:Error {
        return self.handler.handleSubscribeToTask(context, request);
    }

    isolated resource function get tasks/[string id](a2a:Context context,
            a2a:GetTaskRequest request)
            returns a2a:Task|a2a:Error {
        return self.handler.handleGetTask(context, request);
    }

    isolated resource function get tasks(a2a:Context context, a2a:ListTasksRequest request)
            returns a2a:ListTasksResponse|a2a:Error {
        return self.handler.handleListTasks(context, request);
    }

    isolated resource function post tasks/[string id]/cancel(a2a:Context context,
            a2a:CancelTaskRequest request)
            returns a2a:Task|a2a:Error {
        return self.handler.handleCancelTask(context, request);
    }
}
