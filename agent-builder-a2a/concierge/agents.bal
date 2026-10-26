import ballerina/ai;

final ai:Agent concierge = check new (
    systemPrompt = {role: "Concierge", instructions: string `Help the user. When a question is about planning a trip, hand it to the trip planner agent and restate its answer in your own words. Answer everything else yourself.`}, model = claudeModel, tools = [tripPlannerAgent]
);
