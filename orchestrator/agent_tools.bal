// Discover-and-delegate tools: a small, generic set the real ballerina/ai
// Agent uses to reach any of the five real downstream agents, instead of
// twenty named per-agent, per-operation tools. Mirrors the real pattern
// WSO2 Integrator: BI itself generates (see
// ~/WSO2Integrator/wso2-integrator-a2a/a2ademoassistant/functions.bal) --
// a small KnownAgent registry, real AgentCards resolved on demand via
// discoverAgents, and delegateToAgent/cancelAgentTask/getAgentTaskStatus/
// listAgentTasks acting on whichever agent name the model picks.
//
// No agent's real Agent Card is resolved until something actually
// delegates to it -- unlike the previous module-level `final a2a:Client`
// per agent, which resolved all five eagerly at module init and meant the
// whole orchestrator failed to boot if any one agent was down.
import ballerina/a2a;
import ballerina/ai;
import ballerina/lang.runtime;
import ballerina/os;
import ballerina/uuid;

// Reads an env var, falling back to a default when unset or empty -- the
// same rule os:getEnv's callers below already apply per-field for URLs,
// pulled out once so the credential fields below don't repeat it a third
// and fourth time.
isolated function envOrDefault(string name, string default) returns string {
    string value = os:getEnv(name);
    return value != "" ? value : default;
}

type KnownAgent record {|
    string name;
    string url;
    // The scheme name this agent's own AgentCard declares for its
    // extended-card gating, paired with the env var the actual credential
    // is read from -- () for the three agents that declare no
    // extended-card auth at all. Deliberately not the credential's value:
    // that would mean baking a fallback secret in here (removed on
    // purpose -- see below), and it would go stale the moment someone
    // rotated the token without restarting the orchestrator. Reading
    // os:getEnv(envVarName) fresh in extendedCardComparison instead means
    // there is exactly one string literal for each demo secret in the
    // whole repo now: none. Same env var name the agent itself reads
    // server-side (PAYROLL_ADMIN_TOKEN in application.properties,
    // PEOPLEOPS_STAFF_TOKEN in auth.py), so client and server always agree
    // without either hardcoding the other's value.
    //
    // No fallback if the env var is unset: this used to default to
    // "demo-staff-secret"/"demo-payroll-admin-secret", the same fixed
    // strings the agents themselves used to default to before adopting
    // real env-var checks. Two independently-hardcoded copies of the same
    // secret happening to match is not the same as an env var actually
    // being read -- it just meant nobody would notice if the two drifted.
    // Removed to make that failure loud instead: with no credential
    // configured, extendedCardComparison says so explicitly rather than
    // silently presenting a guess.
    //
    // Tuple: [schemeName, credentialEnvVarName].
    [string, string]? extendedCardScheme?;
|};

// Local-process defaults (127.0.0.1); each is overridable via its own env
// var to the real Docker Compose service name (e.g. "http://parking:8000")
// in containerized deployment, since 127.0.0.1 inside a container refers
// to that container itself, not a sibling one. These are endpoints, not
// secrets, so defaulting them carries none of the risk defaulting a
// credential does.
final KnownAgent[] & readonly knownAgents = [
    {name: "Parking", url: envOrDefault("PARKING_URL", "http://127.0.0.1:8000")},
    {name: "DigiOps", url: envOrDefault("DIGIOPS_URL", "http://127.0.0.1:8001")},
    {
        name: "PeopleOperations",
        url: envOrDefault("PEOPLEOPS_URL", "http://127.0.0.1:8002"),
        extendedCardScheme: ["bearer-staff", "PEOPLEOPS_STAFF_TOKEN"]
    },
    {
        name: "Payroll",
        url: envOrDefault("PAYROLL_URL", "http://127.0.0.1:8003"),
        extendedCardScheme: ["bearer-admin", "PAYROLL_ADMIN_TOKEN"]
    },
    {name: "TravelExpense", url: envOrDefault("TRAVEL_EXPENSE_URL", "http://127.0.0.1:8004")}
];

isolated map<a2a:Client> agentClients = {};

isolated function findKnownAgent(string agentName) returns KnownAgent|error {
    foreach KnownAgent known in knownAgents {
        if known.name == agentName {
            return known;
        }
    }
    return error("Unknown agent: " + agentName);
}

// Resolves (and caches) a real a2a:Client for the named agent, only when
// something actually needs to talk to it.
isolated function getAgentClient(string agentName) returns a2a:Client|error {
    KnownAgent known = check findKnownAgent(agentName);
    lock {
        a2a:Client? existing = agentClients[agentName];
        if existing is a2a:Client {
            return existing;
        }
        a2a:Client fresh = check new (known.url);
        agentClients[agentName] = fresh;
        return fresh;
    }
}

isolated function joinPartsText(a2a:Part[] parts) returns string {
    string[] texts = [];
    foreach a2a:Part part in parts {
        string? text = part?.text;
        if text is string {
            texts.push(text);
        }
    }
    return string:'join(" ", ...texts);
}

isolated function taskText(a2a:Task task) returns string {
    a2a:Artifact[] artifacts = task.artifacts;
    if artifacts.length() > 0 {
        return joinPartsText(artifacts[artifacts.length() - 1].parts);
    }
    a2a:Message? statusMessage = task.status?.message;
    if statusMessage is a2a:Message {
        return joinPartsText(statusMessage.parts);
    }
    return "(no textual response from the agent — task state: " + task.status.state.toString() + ")";
}

// Includes the real task id in every Task-backed reply so the model can
// recall it (via its own conversation memory) if the employee later asks
// to check on, or cancel, the same request.
isolated function summarizeTask(a2a:Task task) returns string {
    return "[" + task.status.state.toString() + "] " + taskText(task) + " (task id: " + task.id + ")";
}

isolated function summarizeTasks(a2a:Task[] tasks) returns string {
    if tasks.length() == 0 {
        return "No tasks found.";
    }
    string[] lines = [];
    foreach a2a:Task task in tasks {
        lines.push(summarizeTask(task));
    }
    return string:'join("\n", ...lines);
}

isolated function extractResponseText(a2a:Task|a2a:Message result) returns string {
    if result is a2a:Message {
        return joinPartsText(result.parts);
    } else if result is a2a:Task {
        return summarizeTask(result);
    }
    panic error("unreachable: result is always a2a:Task or a2a:Message");
}

// Some downstream agents (onboarding, hardware provisioning) run for
// real minutes; most finish in well under a second. returnImmediately
// makes every sendMessage call return as soon as the task is created
// (SUBMITTED), regardless of how long the real work takes -- so the
// only way to keep today's fast agents feeling synchronous is to poll
// here, bounded, rather than block on sendMessage itself (which the
// underlying http:Client's stock 30s timeout would risk on a slow one
// anyway). A still-non-terminal task after the window just falls
// through to extractResponseText/summarizeTask as-is -- that already
// produces an honest "still working, here's the task id" reply with no
// new formatting needed.
final decimal MAX_INITIAL_WAIT_SECONDS = 20d;
final decimal POLL_INTERVAL_SECONDS = 0.5d;

isolated function isSettled(a2a:TaskState state) returns boolean {
    return state == a2a:TASK_STATE_COMPLETED || state == a2a:TASK_STATE_FAILED
        || state == a2a:TASK_STATE_CANCELED || state == a2a:TASK_STATE_REJECTED
        || state == a2a:TASK_STATE_INPUT_REQUIRED || state == a2a:TASK_STATE_AUTH_REQUIRED;
}

// Polls a still-in-progress task, checking immediately first (no leading
// sleep -- returnImmediately means the very first check happens right at
// task-creation time regardless of work duration, so a fixed sleep before
// it would just be dead latency on every call), then sleeping between
// subsequent attempts, up to MAX_INITIAL_WAIT_SECONDS total.
isolated function pollUntilSettled(a2a:Client agentClient, a2a:Task initial) returns a2a:Task|error {
    a2a:Task task = initial;
    decimal elapsed = 0d;
    boolean first = true;
    while !isSettled(task.status.state) && elapsed < MAX_INITIAL_WAIT_SECONDS {
        if !first {
            runtime:sleep(POLL_INTERVAL_SECONDS);
            elapsed += POLL_INTERVAL_SECONDS;
        }
        first = false;
        task = check agentClient->getTask(task.id);
    }
    return task;
}

isolated function sendToAgent(a2a:Client agentClient, string message) returns string|error {
    a2a:Message msg = {messageId: uuid:createType4AsString(), role: a2a:ROLE_USER, parts: [{text: message}]};
    a2a:Task|a2a:Message result = check agentClient->sendMessage(msg, config = {returnImmediately: true});
    if result is a2a:Task {
        a2a:Task settled = check pollUntilSettled(agentClient, result);
        return extractResponseText(settled);
    }
    return extractResponseText(result);
}

isolated function cancelTaskOn(a2a:Client agentClient, string taskId) returns string|error {
    a2a:Task result = check agentClient->cancelTask(taskId);
    return summarizeTask(result);
}

isolated function getTaskStatusOn(a2a:Client agentClient, string taskId) returns string|error {
    a2a:Task result = check agentClient->getTask(taskId);
    return summarizeTask(result);
}

isolated function listTasksOn(a2a:Client agentClient) returns string|error {
    a2a:ListTasksResult result = check agentClient->listTasks();
    return summarizeTasks(result.tasks);
}

isolated function skillIdsOf(a2a:AgentCard card) returns string {
    if card.skills.length() == 0 {
        return "none";
    }
    return string:'join(", ", ...card.skills.map(s => s.id));
}

// Proves extended-card auth gating in one call instead of two: fetches the
// card once with no credential and, only when this agent genuinely declares
// one (Payroll, PeopleOperations) and a real credential is actually
// configured for it, once more authenticated, then reports the skill-count
// difference -- the same comparison verification/payroll and
// verification/peopleoperations already make from a terminal, just
// reachable from chat too.
//
// The authenticated fetch goes through a2a:CredentialProvider rather than
// a hand-built header: the credential is filed under the scheme name
// known.extendedCardScheme carries, and the client resolves it against
// that agent's own declared securitySchemes -- the same card-driven
// discovery a caller with no prior knowledge of "Authorization: Bearer"
// would go through, not a shortcut past it.
isolated function extendedCardComparison(string agentName) returns string|error {
    KnownAgent known = check findKnownAgent(agentName);
    a2a:Client plainClient = check getAgentClient(agentName);
    a2a:AgentCard|error unauthCard = plainClient->getExtendedAgentCard();

    [string, string]? scheme = known?.extendedCardScheme;
    if scheme is () {
        if unauthCard is error {
            return string `${agentName} does not declare extended-card auth gating, and its extended card fetch failed anyway: ${unauthCard.message()}`;
        }
        return string `${agentName} declares no extended-card auth gating -- its public card already has ${unauthCard.skills.length()} skill(s): ${skillIdsOf(unauthCard)}`;
    }

    [string, string] [schemeName, credentialEnvVar] = scheme;
    string credential = os:getEnv(credentialEnvVar);
    if credential == "" {
        // Deliberately not silently substituted with a hardcoded demo
        // value -- see KnownAgent's own comment for why. This state is
        // real and worth reporting plainly rather than hiding behind a
        // fallback that used to make it look configured when it wasn't.
        string unauthDesc = unauthCard is error
            ? string `rejected outright (${unauthCard.message()})`
            : string `${unauthCard.skills.length()} skill(s): ${skillIdsOf(unauthCard)}`;
        return string `${agentName} declares extended-card auth gating (scheme "${schemeName}"), ` +
            string `but no credential is configured -- set ${credentialEnvVar} in .env and restart ` +
            string `both the agent and the orchestrator to test it. Unauthenticated: ${unauthDesc}.`;
    }

    a2a:InMemoryCredentialStore store = new ({[schemeName]: credential});
    a2a:Client authedClient = check new (known.url, credentials = store);
    a2a:AgentCard authedCard = check authedClient->getExtendedAgentCard();
    string unauthDesc = unauthCard is error
        ? string `rejected outright (${unauthCard.message()})`
        : string `${unauthCard.skills.length()} skill(s): ${skillIdsOf(unauthCard)}`;
    return string `${agentName} extended-card auth gating is real -- unauthenticated: ${unauthDesc}; authenticated: ${authedCard.skills.length()} skill(s): ${skillIdsOf(authedCard)}`;
}

# Fetches the real Agent Card (name, description, skills) for every known
# WSO2 agent, so you can see what each one actually does and pick the
# right one to delegate to. Call this once near the start of a
# conversation, not before every request.
#
# + return - a JSON array of {name, description, skills} per agent, or an
# error if a card couldn't be fetched
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function discoverAgents() returns json|error {
    json[] cards = [];
    foreach KnownAgent known in knownAgents {
        a2a:AgentCard|error card = a2a:resolveAgentCard(known.url);
        if card is a2a:AgentCard {
            cards.push({name: known.name, description: card.description, skills: card.skills});
        } else {
            cards.push({name: known.name, 'error: "Failed to fetch this agent's card: " + card.message()});
        }
    }
    return cards;
}

# Sends a new request, in natural language, to a specific known WSO2
# agent by its exact name (from discoverAgents — not a URL).
#
# + agentName - the target agent's exact name, e.g. "Parking"
# + message - the employee's request, in natural language
# + return - the agent's real reply, or an error if the request failed
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function delegateToAgent(string agentName, string message) returns string|error {
    a2a:Client agentClient = check getAgentClient(agentName);
    return sendToAgent(agentClient, message);
}

# Cancels a pending task on a specific known agent, by its task id from an
# earlier reply.
#
# + agentName - the agent's exact name that the task belongs to
# + taskId - the task id from an earlier reply
# + return - the task's real resulting state, or an error if it failed
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function cancelAgentTask(string agentName, string taskId) returns string|error {
    a2a:Client agentClient = check getAgentClient(agentName);
    return cancelTaskOn(agentClient, taskId);
}

# Checks the real current status of a task on a specific known agent, by
# its task id from an earlier reply.
#
# + agentName - the agent's exact name that the task belongs to
# + taskId - the task id from an earlier reply
# + return - the task's real current state, or an error if it failed
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function getAgentTaskStatus(string agentName, string taskId) returns string|error {
    a2a:Client agentClient = check getAgentClient(agentName);
    return getTaskStatusOn(agentClient, taskId);
}

# Lists every real task a specific known agent has, e.g. every
# reservation, ticket, correction, or claim it's seen.
#
# + agentName - the agent's exact name
# + return - a real summary of every task, or an error if the request failed
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function listAgentTasks(string agentName) returns string|error {
    a2a:Client agentClient = check getAgentClient(agentName);
    return listTasksOn(agentClient);
}

# Checks whether a specific known agent's *extended* AgentCard (its full,
# possibly admin/staff-only skill list) differs from its public one. Use
# this only when explicitly asked to inspect an agent's extended/admin card
# or to verify its auth gating -- never as part of normal task delegation,
# and never before a normal request to that agent.
#
# + agentName - the agent's exact name
# + return - a comparison of the unauthenticated vs. authenticated card, or
# an error if neither fetch succeeded
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function getAgentExtendedCard(string agentName) returns string|error {
    return extendedCardComparison(agentName);
}
