import ballerina/ai;

final ai:Agent tripPlanner = check new (
    systemPrompt = {
        role: "Trip Planner",
        instructions: string `Plan a short, one-day itinerary for the city the user names: 3 to 4 activities, each one sentence. If no city is named, ask which city.`
    },
    model = claudeModel
);
