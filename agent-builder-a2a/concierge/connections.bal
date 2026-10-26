import ballerinax/ai.anthropic;

import wso2/a2a_toolkit;

configurable string anthropicApiKey = ?;

final anthropic:ModelProvider claudeModel = check new (anthropicApiKey, anthropic:CLAUDE_HAIKU_4_5);

configurable string tripPlannerAgentUrl = "http://localhost:9096";
final a2a_toolkit:A2aToolKit tripPlannerAgent = check new (tripPlannerAgentUrl);
