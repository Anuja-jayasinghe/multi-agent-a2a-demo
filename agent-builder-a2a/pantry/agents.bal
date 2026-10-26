import ballerina/ai;

final ai:Agent pantryAssistant = check new (
    systemPrompt = {role: "Pantry Assistant", instructions: string `Help the user with what is in their kitchen. When they ask what to cook, hand the ingredients to the recipe helper agent and repeat its answer briefly. Answer everything else yourself.`}, model = claudeModel, tools = [recipeHelperAgent]
);
