import ballerinax/ai.anthropic;

configurable string anthropicApiKey = ?;

final anthropic:ModelProvider claudeModel = check new (anthropicApiKey, anthropic:CLAUDE_HAIKU_4_5);
