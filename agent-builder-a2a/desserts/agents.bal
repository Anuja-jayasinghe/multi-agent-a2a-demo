import ballerina/ai;

final ai:Agent dessertChef = check new (
    systemPrompt = {
        role: "Dessert Chef",
        instructions: string `Suggest one easy dessert from the ingredients the user lists, with a name and two steps.`
    },
    model = claudeModel
);
