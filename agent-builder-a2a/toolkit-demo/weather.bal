// Weather Agent: open, no credential. Port 9201.

import ballerina/a2a;

configurable int weatherPort = 9201;

listener a2a:RestListener weatherListener = new (weatherPort);

type Forecast record {|
    string now;
    string saturday;
    string sunday;
|};

final readonly & map<Forecast> FORECASTS = {
    "Colombo": {now: "31°C, humid, scattered clouds", saturday: "30°C, afternoon showers likely (70%)", sunday: "31°C, mostly sunny"},
    "Kandy": {now: "26°C, light breeze, partly cloudy", saturday: "25°C, light rain in the evening", sunday: "27°C, clear skies"},
    "Galle": {now: "29°C, sunny, sea breeze", saturday: "29°C, sunny, calm sea", sunday: "28°C, passing showers"},
    "London": {now: "9°C, overcast", saturday: "8°C, drizzle most of the day", sunday: "11°C, bright spells"},
    "Paris": {now: "12°C, partly sunny", saturday: "13°C, dry and mild", sunday: "10°C, showers from midday"},
    "Tokyo": {now: "15°C, clear", saturday: "16°C, sunny", sunday: "14°C, cloudy, chance of rain (40%)"},
    "New York": {now: "7°C, windy", saturday: "5°C, cold and clear", sunday: "9°C, cloudy"},
    "San Francisco": {now: "16°C, morning fog", saturday: "18°C, fog clearing by noon", sunday: "19°C, sunny"}
};

isolated class WeatherExecutor {
    *a2a:AgentExecutor;

    public isolated function execute(a2a:RequestContext context, a2a:TaskUpdater updater)
            returns a2a:Message|a2a:Error? {
        string text = requestText(context);
        string? city = cityIn(text);
        if city is () {
            return reply(context, string `I have weather for ${knownCities()}. Which city?`);
        }
        Forecast f = FORECASTS.get(city);
        boolean weekend = text.toLowerAscii().includes("weekend") || text.toLowerAscii().includes("forecast")
            || text.toLowerAscii().includes("saturday") || text.toLowerAscii().includes("sunday");
        if weekend {
            return reply(context, string `Weekend forecast for ${city}: Saturday ${f.saturday}; Sunday ${f.sunday}.`);
        }
        return reply(context, string `Right now in ${city}: ${f.now}. This weekend: Saturday ${f.saturday}; Sunday ${f.sunday}.`);
    }
}

@a2a:ServiceConfig {
    agentCard: {
        name: "Weather Agent",
        description: "Current conditions and the weekend forecast for a city. Ask in plain language, for example "
            + "\"What's the weather in Kandy this weekend?\".",
        version: "1.2.0",
        provider: DEMO_PROVIDER,
        documentationUrl: "https://a2a-protocol.org/latest/specification/",
        capabilities: {streaming: false, pushNotifications: false},
        defaultInputModes: ["text/plain"],
        defaultOutputModes: ["text/plain"],
        supportedInterfaces: [],
        skills: [
            {
                id: "current-weather",
                name: "Current weather",
                description: "Temperature and conditions in a city right now.",
                tags: ["weather", "conditions"],
                examples: ["What's the weather in Colombo right now?", "Is it cold in London?"]
            },
            {
                id: "weekend-forecast",
                name: "Weekend forecast",
                description: "Saturday and Sunday forecast for a city, including the chance of rain.",
                tags: ["weather", "forecast", "weekend"],
                examples: ["Will it rain in Kandy this weekend?", "Weekend forecast for Paris"]
            }
        ]
    }
}
isolated service on weatherListener {
    private final a2a:DefaultHandler handler = new (new WeatherExecutor());

    isolated resource function post message\:send(a2a:Context context, a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return self.handler.handleSendMessage(context, request);
    }
}
