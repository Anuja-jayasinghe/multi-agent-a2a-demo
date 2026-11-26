// Currency Agent: HTTP Basic, users from Config.toml. Port 9202.

import ballerina/a2a;

configurable int currencyPort = 9202;

listener a2a:RestListener currencyListener = new (currencyPort,
    auth = [{fileUserStoreConfig: {}}]
);

// Units of each currency for one US dollar
final readonly & map<decimal> PER_USD = {
    "USD": 1, "LKR": 298.40, "EUR": 0.92, "GBP": 0.79, "JPY": 151.20, "INR": 83.40, "AUD": 1.52, "SGD": 1.34
};

isolated class CurrencyExecutor {
    *a2a:AgentExecutor;

    public isolated function execute(a2a:RequestContext context, a2a:TaskUpdater updater)
            returns a2a:Message|a2a:Error? {
        string text = requestText(context);
        string[] codes = [];
        decimal amount = 1;
        foreach string word in re `[\s,]+`.split(text.toUpperAscii()) {
            string token = re `[^A-Z0-9.]`.replaceAll(word, "");
            if PER_USD.hasKey(token) && codes.indexOf(token) is () {
                codes.push(token);
            } else {
                decimal|error parsed = decimal:fromString(token);
                if parsed is decimal {
                    amount = parsed;
                }
            }
        }
        string supported = string:'join(", ", ...PER_USD.keys());
        if codes.length() == 0 {
            return reply(context, string `I convert between ${supported}. For example: "100 USD to LKR".`);
        }
        if codes.length() == 1 {
            string code = codes[0];
            return reply(context, string `1 USD = ${PER_USD.get(code).round(2)} ${code} (demo rates, fixed).`);
        }
        decimal converted = amount / PER_USD.get(codes[0]) * PER_USD.get(codes[1]);
        return reply(context, string `${amount} ${codes[0]} = ${converted.round(2)} ${codes[1]} (demo rates, fixed).`);
    }
}

@a2a:ServiceConfig {
    agentCard: {
        name: "Currency Agent",
        description: "Converts amounts between currencies and lists exchange rates. Callers sign in with HTTP Basic.",
        version: "2.0.1",
        provider: DEMO_PROVIDER,
        documentationUrl: "https://a2a-protocol.org/latest/specification/",
        capabilities: {streaming: false, pushNotifications: false},
        defaultInputModes: ["text/plain"],
        defaultOutputModes: ["text/plain"],
        supportedInterfaces: [],
        skills: [
            {
                id: "convert",
                name: "Convert currency",
                description: "Converts an amount from one currency to another.",
                tags: ["currency", "conversion", "travel"],
                examples: ["Convert 150 USD to LKR", "How much is 50 GBP in EUR?"]
            },
            {
                id: "rates",
                name: "Exchange rate",
                description: "The rate of a currency against the US dollar.",
                tags: ["currency", "rates"],
                examples: ["What's the LKR rate?"]
            }
        ]
    }
}
isolated service on currencyListener {
    private final a2a:DefaultHandler handler = new (new CurrencyExecutor());

    isolated resource function post message\:send(a2a:Context context, a2a:SendMessageRequest request)
            returns a2a:Task|a2a:Message|a2a:Error {
        return self.handler.handleSendMessage(context, request);
    }
}
