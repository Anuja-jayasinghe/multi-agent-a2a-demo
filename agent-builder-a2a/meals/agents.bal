import ballerina/ai;

final ai:Agent mealPlanner = check new (
    systemPrompt = {
        role: "Meal Planner",
        instructions: string `Plan three simple dinners for the week from the ingredients the user lists, one line each.`
    },
    model = claudeModel
);
