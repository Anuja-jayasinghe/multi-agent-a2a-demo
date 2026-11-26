// Shared by the three demo agents: reading the request text and building a reply.

import ballerina/a2a;
import ballerina/uuid;

// Who publishes the demo agents, shown on each Agent Card
final a2a:AgentProvider & readonly DEMO_PROVIDER = {
    organization: "Agent Builder A2A Demo",
    url: "https://a2a-protocol.org"
};

// The cities the demo agents know about, keyed by lower-case name
final readonly & string[] CITIES = ["colombo", "kandy", "galle", "london", "paris", "tokyo", "new york", "san francisco"];

isolated function requestText(a2a:RequestContext context) returns string =>
    string:'join(" ", ...from a2a:Part part in context.message.parts select part?.text ?: "").trim();

isolated function reply(a2a:RequestContext context, string text) returns a2a:Message => {
    messageId: uuid:createType4AsString(),
    contextId: context.message.contextId,
    role: a2a:ROLE_AGENT,
    parts: [{text}]
};

# The first known city named in the text.
#
# + text - the request text
# + return - the city in title case, or `()` if none is named
isolated function cityIn(string text) returns string? {
    string lower = text.toLowerAscii();
    foreach string city in CITIES {
        if lower.includes(city) {
            return titleCase(city);
        }
    }
    return ();
}

isolated function titleCase(string words) returns string {
    string[] out = from string word in re ` `.split(words)
        where word.length() > 0
        select word.substring(0, 1).toUpperAscii() + word.substring(1);
    return string:'join(" ", ...out);
}

isolated function knownCities() returns string =>
    string:'join(", ", ...from string city in CITIES select titleCase(city));
