// City Events Agent: Bearer JWT signed with a demo HMAC secret. Port 9203.

import ballerina/a2a;

configurable int eventsPort = 9203;
configurable string eventsJwtSecret = ?;

const EVENTS_ISSUER = "toolkit-demo";
const EVENTS_AUDIENCE = "city-events-agent";

listener a2a:RestListener eventsListener = new (eventsPort,
    auth = [{jwtValidatorConfig: {issuer: EVENTS_ISSUER, audience: EVENTS_AUDIENCE, signatureConfig: {secret: eventsJwtSecret}}}]
);

type CityGuide record {|
    string[] events;
    string[] food;
|};

final readonly & map<CityGuide> GUIDES = {
    "Colombo": {events: ["Saturday: Good Market at Racecourse (10:00-17:00)", "Sunday: sunset walk at Galle Face Green"],
        food: ["Ministry of Crab (seafood)", "Upali's (Sri Lankan rice and curry)"]},
    "Kandy": {events: ["Saturday: Temple of the Tooth evening puja (18:30)", "Sunday: Royal Botanical Gardens, Peradeniya"],
        food: ["The Empire Cafe (rice and curry)", "Balaji Dosai (South Indian)"]},
    "Galle": {events: ["Saturday: Galle Fort ramparts walk at sunset", "Sunday: Unawatuna beach and snorkelling"],
        food: ["Pedlar's Inn (cafe)", "Lucky Fort Restaurant (curry tasting)"]},
    "London": {events: ["Saturday: Borough Market and the South Bank", "Sunday: Columbia Road Flower Market"],
        food: ["Dishoom (Bombay cafe)", "Padella (fresh pasta)"]},
    "Paris": {events: ["Saturday: Musée d'Orsay late opening", "Sunday: Marché des Enfants Rouges"],
        food: ["Le Comptoir du Relais (bistro)", "L'As du Fallafel"]},
    "Tokyo": {events: ["Saturday: teamLab Planets, Toyosu", "Sunday: Yoyogi Park and Harajuku"],
        food: ["Ichiran (ramen)", "Tsukiji Outer Market (sushi breakfast)"]},
    "New York": {events: ["Saturday: The High Line and Chelsea Market", "Sunday: Brooklyn Flea, DUMBO"],
        food: ["Joe's Pizza", "Katz's Delicatessen"]},
    "San Francisco": {events: ["Saturday: Ferry Building farmers market", "Sunday: Golden Gate Park and the de Young"],
        food: ["Tartine Bakery", "La Taqueria (Mission burritos)"]}
};

isolated class EventsExecutor {
    *a2a:AgentExecutor;

    public isolated function execute(a2a:RequestContext context, a2a:TaskUpdater updater)
            returns a2a:Message|a2a:Error? {
        string text = requestText(context);
        string? city = cityIn(text);
        if city is () {
            return reply(context, string `I have weekend picks for ${knownCities()}. Which city?`);
        }
        CityGuide guide = GUIDES.get(city);
        string lower = text.toLowerAscii();
        boolean foodOnly = lower.includes("eat") || lower.includes("food") || lower.includes("restaurant")
            || lower.includes("dinner") || lower.includes("lunch");
        string food = string:'join("; ", ...guide.food);
        if foodOnly {
            return reply(context, string `Where to eat in ${city}: ${food}.`);
        }
        return reply(context, string `This weekend in ${city}: ${string:'join("; ", ...guide.events)}. Where to eat: ${food}.`);
    }
}

@a2a:ServiceConfig {
    agentCard: {
        name: "City Events Agent",
        description: "What's on this weekend in a city, and where to eat. Callers send a bearer token.",
        version: "0.9.0",
        provider: DEMO_PROVIDER,
        documentationUrl: "https://a2a-protocol.org/latest/specification/",
        capabilities: {streaming: false, pushNotifications: false},
        defaultInputModes: ["text/plain"],
        defaultOutputModes: ["text/plain"],
        supportedInterfaces: [],
        skills: [
            {
                id: "weekend-events",
                name: "Weekend events",
                description: "Markets, sights and events on Saturday and Sunday in a city.",
                tags: ["events", "weekend", "travel"],
                examples: ["What's on in Galle this weekend?", "Things to do in Tokyo on Saturday"]
            },
            {
                id: "restaurant-picks",
                name: "Where to eat",
                description: "Two local places to eat in a city.",
                tags: ["food", "restaurants"],
                examples: ["Where should we eat in Colombo?"]
            }
        ]
    }
}
isolated service on eventsListener {
    private final a2a:DefaultHandler handler = new (new EventsExecutor());

    isolated resource function post message\:send(a2a:Context context, a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return self.handler.handleSendMessage(context, request);
    }
}
