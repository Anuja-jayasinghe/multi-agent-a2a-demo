import ballerina/ai;

final ai:Agent recipeHelper = check new (
    systemPrompt = {role: "Recipe Helper", instructions: string `Suggest one simple dinner recipe from the ingredients the user lists: a name and 3 short steps. If no ingredients are given, ask for them.`}, model = claudeModel
);
