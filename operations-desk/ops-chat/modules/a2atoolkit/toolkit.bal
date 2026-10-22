// An ai:BaseToolKit that turns one A2A agent into ready-made agent tools --
// the same shape ai:McpToolKit already gives one MCP server.
//
// One instance wraps one agent, placed directly in ai:Agent's tools array
// alongside as many others as needed, exactly like multiple McpToolKit
// instances sit side by side:
//
// ```ballerina
// A2aToolKit tripPlanner = check new ("http://127.0.0.1:8000");
// A2aToolKit packingAssistant = check new ("http://127.0.0.1:8003", secret = adminToken);
// ai:Agent concierge = check new (systemPrompt = {...}, model = m,
//     tools = [tripPlanner, packingAssistant]);
// ```
//
// Earlier revision held a whole agent *registry* in one instance
// (`A2aToolKit(agents: A2aAgentSpec[])`), with generic tools taking an
// `agentName` parameter so the model could pick among them. That doesn't
// match how every other toolkit in this ecosystem works -- ai:McpToolKit is
// one instance per server (module-ballerina-ai's toolkit.bal), not one
// instance holding a list of servers -- so this revision switches to the
// same one-per-agent shape: the tools array itself is the discovery
// mechanism, not a generated `discoverAgents` tool.
//
// The real consequence of that switch: A2A's tool surface is
// protocol-fixed -- every agent gets the same delegate/status/cancel/list
// actions -- unlike MCP's server-chosen tool names, so two instances in the
// same tools array would otherwise generate identically named tools with no
// way to tell them apart. Every generated tool name is qualified by the
// agent's own Card name instead (`delegateToTripPlanner`, not
// `delegateToAgent`) to avoid exactly that collision. Two agents with the
// same Card name still collide -- give them meaningfully different names,
// the same expectation ai:McpToolKit places on whoever names two McpToolKit
// variables identically.
//
// Second revision: rebuilt against the current ballerina/a2a 0.1.0 client
// API (`a2a:RestClient`, request-record calls -- `a2a:Client` is
// package-private by design, see client.bal's own doc comment) instead of
// the original 0.2.1 prototype's `a2a:Client`/positional-argument API,
// which the published 0.2.1 bala no longer matches either. Adds task
// continuation (`delegateToAgent`'s optional `taskId`) and a `clientConfig`,
// so an agent that needs e.g. `httpVersion: HTTP_1_1` (the real a2a-java
// reference server -- see a2a-library-testing's RESULTS.md, Finding 5) is
// reachable; without it there was no way to pass `http:ClientConfiguration`
// through at all.
//
// `connect` is the one place that names `a2a:RestClient` -- the seam a
// JSON-RPC or gRPC client plugs into once the library speaks those
// bindings, with nothing else in this file changing.

import ballerina/a2a;
import ballerina/ai;
import ballerina/http;
import ballerina/lang.runtime;
import ballerina/uuid;

# Marker subtype for an A2A-backed toolkit, mirroring ai:McpBaseToolKit --
# itself just `*BaseToolKit` with no added members. Its only purpose today
# is letting a future compiler-plugin pass classify an A2aToolKit the same
# way module-ballerina-ai's plugin already classifies an McpToolKit as
# MCP_TOOLKIT instead of the generic TOOLKIT kind (ballerina/ai's
# agent.bal); that classification work itself is out of scope here.
public type A2aBaseToolKit distinct isolated object {
    *ai:BaseToolKit;
};

# Which operations to generate tools for.
#
# Defaults to the four an orchestrator actually needs day to day. The rest
# are opt-in because each one adds a tool the model has to choose between,
# and an ai:Agent with twenty tools routes measurably worse than one with
# five.
public type A2aToolSet record {|
    # delegateToAgent, getAgentTaskStatus, cancelAgentTask, listAgentTasks --
    # the core request/response surface.
    boolean core = true;
    # streamFromAgent and subscribeToAgentTask. Both collect the stream to
    # completion before returning, since a tool call returns once; the
    # value over `delegateToAgent` is that intermediate progress is
    # captured rather than only the final state.
    boolean streaming = false;
    # getAgentExtendedCard. Only useful for an agent constructed with a
    # `secret`, and deliberately separate: an agent that can read extended
    # cards is doing something privileged.
    boolean extendedCard = false;
    # The four push-notification config operations.
    boolean pushNotifications = false;
|};

# Turns one A2A agent into `ai:ToolConfig`s an `ai:Agent` can use directly.
public isolated class A2aToolKit {
    *A2aBaseToolKit;

    # Human-readable, straight from the card's own `name` field -- used in
    # tool descriptions so the model knows which agent a tool talks to.
    private final string agentName;
    private final ai:ToolConfig[] & readonly tools;
    # Built eagerly, in `init`, alongside the card -- unlike the card, a
    # client has nowhere readonly-safe to keep the `http:ClientConfiguration`
    # it was built from (that type isn't Cloneable), so it has to be built
    # while that config is still a local, in scope, rather than
    # reconstructed lazily from stored state later. `a2a:RestClient` is
    # itself an isolated client type, so holding one as `final` object state
    # needs no `lock` to read.
    private final a2a:RestClient agentClient;

    # + agent - The agent's base URL, or an already-resolved `a2a:AgentCard`.
    #           Pass a card when you already hold one -- from
    #           `resolveAgentCardCached`, or one whose signature you
    #           verified yourself. It is used as given rather than
    #           re-fetched, so a verified card stays the verified card.
    # + secret - The credential, for an agent that gates something. The
    #            *scheme* it is filed under is read from the card's own
    #            `securityRequirements`, so nothing here assumes a header
    #            shape -- only the secret is supplied. Omit for an agent
    #            that gates nothing, which is most of them.
    # + clientConfig - Passed through to card resolution (when `agent` is a
    #                  URL) and to the client, unchanged -- `httpVersion`,
    #                  `timeout`, `auth`, TLS, and every other
    #                  `http:ClientConfiguration` field. Most agents need
    #                  nothing here; it exists for the ones that do (a
    #                  server that refuses HTTP/2 with prior knowledge, for
    #                  example).
    # + toolSet - Which operation groups to generate tools for
    public isolated function init(a2a:AgentCard|string agent, string? secret = (),
            http:ClientConfiguration clientConfig = {}, A2aToolSet toolSet = {}) returns ai:Error? {
        a2a:AgentCard card;
        if agent is a2a:AgentCard {
            card = agent;
        } else {
            a2a:AgentCard|error resolved = a2a:resolveAgentCard(agent, clientConfig = clientConfig);
            if resolved is error {
                return error ai:Error(string `could not resolve the Agent Card for ${agent} `
                    + string `(${resolved.message()})`);
            }
            card = resolved;
        }

        string name = card.name;
        string? schemeName = ();
        a2a:SecurityRequirement[]? securityRequirements = card.securityRequirements;
        if securityRequirements is a2a:SecurityRequirement[] && securityRequirements.length() > 0 {
            string[] schemes = securityRequirements[0].keys();
            if schemes.length() > 1 {
                // An AND across several schemes needs several secrets; a
                // single `secret` cannot say which is which.
                return error ai:Error(string `agent "${name}" requires ${schemes.length()} `
                    + string `security schemes together (${string:'join(", ", ...schemes)}), which a `
                    + string `single secret cannot satisfy.`);
            }
            if schemes.length() == 1 {
                schemeName = schemes[0];
            }
        }
        if secret is string && schemeName is () {
            return error ai:Error(string `a secret was supplied for agent "${name}", but its card `
                + string `declares no security scheme to file it under.`);
        }

        a2a:RestClient|error agentClient = connect(card, schemeName, secret, clientConfig);
        if agentClient is error {
            return error ai:Error(string `could not connect to agent "${name}" (${agentClient.message()})`);
        }
        self.agentName = name;
        self.agentClient = agentClient;

        // Built inline rather than in a helper method: Ballerina forbids
        // calling a method on `self` until every final field is assigned,
        // and `tools` is the last one. Taking a *reference* to a method
        // (`self.delegateToAgent`) is fine here -- the same thing
        // ai:McpToolKit does with `self.callTool`.
        string suffix = toolSuffix(name);
        // Baked into delegateTo<Agent>'s description so the model has what
        // it needs to decide whether this agent fits a request, without a
        // separate discovery tool call -- the same way an ai:McpToolKit's
        // tool descriptions come straight from the MCP server, not from a
        // "list servers" round trip the model has to make itself.
        string[] skillDescriptions = from a2a:AgentSkill skill in card.skills select skill.description;
        string about = skillDescriptions.length() > 0
            ? string ` ${card.description} Skills: ${string:'join("; ", ...skillDescriptions)}.`
            : string ` ${card.description}`;

        ai:ToolConfig[] configs = [];

        if toolSet.core {
            configs.push({
                name: string `delegateTo${suffix}`,
                description: string `Sends a natural-language request to "${name}" and returns its `
                    + string `reply. Omit taskId for a fresh question or action. Pass taskId to continue `
                    + string `an existing task instead -- for example, answering a clarifying question `
                    + string `the agent asked.` + about,
                parameters: schemaOf({
                    "message": {"type": "string", "description": "The request, in natural language."},
                    "taskId": {"type": "string",
                        "description": "Optional. An existing task id from this agent to continue, "
                            + "instead of starting a new task."}
                }, ["message"]),
                caller: self.delegateToAgent
            });
            configs.push({
                name: string `get${suffix}TaskStatus`,
                description: string `Fetches the CURRENT state of an existing task on "${name}" by id. `
                    + string `Always call this fresh when asked about a task -- never answer a status `
                    + string `question from earlier conversation, because the real state may have `
                    + string `changed since.`,
                parameters: taskIdSchema(),
                caller: self.getAgentTaskStatus
            });
            configs.push({
                name: string `cancel${suffix}Task`,
                description: string `Cancels an in-progress task on "${name}" by id.`,
                parameters: taskIdSchema(),
                caller: self.cancelAgentTask
            });
            configs.push({
                name: string `list${suffix}Tasks`,
                description: string `Lists every task "${name}" knows about. No task id needed.`,
                parameters: (),
                caller: self.listAgentTasks
            });
        }

        if toolSet.streaming {
            configs.push({
                name: string `streamFrom${suffix}`,
                description: string `Like delegateTo${suffix}, but captures "${name}"'s incremental `
                    + string `progress updates as well as its final answer. Prefer this when the work `
                    + string `is expected to take a while and the progress itself is interesting.`,
                parameters: schemaOf({
                    "message": {"type": "string", "description": "The request, in natural language."}
                }, ["message"]),
                caller: self.streamFromAgent
            });
            configs.push({
                name: string `subscribeTo${suffix}Task`,
                description: string `Watches an existing task on "${name}" by id until it settles, `
                    + string `returning the updates seen along the way.`,
                parameters: taskIdSchema(),
                caller: self.subscribeToAgentTask
            });
        }

        if toolSet.extendedCard {
            configs.push({
                name: string `get${suffix}ExtendedCard`,
                description: string `Fetches "${name}"'s extended Agent Card -- its full skill list, `
                    + string `including any gated skills the public card withholds. Requires this `
                    + string `toolkit to hold a credential for this agent. Use only when explicitly `
                    + string `asked to inspect its extended or admin card, never as part of normal `
                    + string `delegation.`,
                parameters: (),
                caller: self.getAgentExtendedCard
            });
        }

        if toolSet.pushNotifications {
            configs.push({
                name: string `create${suffix}PushNotificationConfig`,
                description: string `Registers a webhook URL to be notified when a task on "${name}" `
                    + string `changes state.`,
                parameters: schemaOf({
                    "taskId": {"type": "string", "description": "The task to watch."},
                    "webhookUrl": {"type": "string", "description": "URL to POST notifications to."}
                }, ["taskId", "webhookUrl"]),
                caller: self.createAgentPushNotificationConfig
            });
            configs.push({
                name: string `list${suffix}PushNotificationConfigs`,
                description: string `Lists the push-notification configs registered for a task on `
                    + string `"${name}".`,
                parameters: taskIdSchema(),
                caller: self.listAgentPushNotificationConfigs
            });
            configs.push({
                name: string `delete${suffix}PushNotificationConfig`,
                description: string `Removes a push-notification config from a task on "${name}" by `
                    + string `its config id.`,
                parameters: schemaOf({
                    "taskId": {"type": "string", "description": "The task the config belongs to."},
                    "configId": {"type": "string", "description": "The config id to delete."}
                }, ["taskId", "configId"]),
                caller: self.deleteAgentPushNotificationConfig
            });
        }
        self.tools = configs.cloneReadOnly();
    }

    public isolated function getTools() returns ai:ToolConfig[] => self.tools;

    // ---- tool implementations -------------------------------------------

    private isolated function delegateToAgent(string message, string? taskId = ()) returns string|error {
        // Message.taskId is an optional `string` field, not `string?` -- it
        // cannot be assigned a nil value directly, so it is only set when a
        // continuation was actually requested.
        a2a:Message outbound = {messageId: uuid:createType4AsString(), role: a2a:ROLE_USER, parts: [{text: message}]};
        if taskId is string {
            outbound.taskId = taskId;
        }
        a2a:Task|a2a:Message result = check self.agentClient->sendMessage({
            message: outbound,
            configuration: {returnImmediately: true}
        });
        if result is a2a:Message {
            return partsText(result.parts);
        }
        // returnImmediately means a Task comes back as soon as it is
        // created, so a fast agent would otherwise always look unfinished.
        // Poll briefly; a still-running task falls through to an honest
        // "here is the state and the id" summary. Task and Message are both
        // open records, so the compiler cannot narrow `result` by
        // elimination after the `is a2a:Message` check above -- an
        // explicit cast is required for the remaining Task arm.
        //
        // For a continuation (taskId given) the Task that comes back is the
        // one as it stood BEFORE this message: still INPUT_REQUIRED, the
        // question the agent asked last time. Reading that as "settled" hands
        // the model the old question while the task is already working on its
        // answer, and the model, believing its reply was ignored, sends it
        // again as a new task. So a continuation is only judged once the task
        // has visibly moved on from that snapshot.
        a2a:Task settled = check self.pollUntilSettled(<a2a:Task>result, taskId is string);
        return summarize(settled);
    }

    private isolated function streamFromAgent(string message) returns string|error {
        stream<a2a:StreamResponse, a2a:Error?> events = check self.agentClient->sendStreamingMessage({
            message: {messageId: uuid:createType4AsString(), role: a2a:ROLE_USER, parts: [{text: message}]}
        });
        return collectStream(events);
    }

    private isolated function subscribeToAgentTask(string taskId) returns string|error {
        stream<a2a:StreamResponse, a2a:Error?> events = check self.agentClient->subscribeToTask({id: taskId});
        return collectStream(events);
    }

    private isolated function getAgentTaskStatus(string taskId) returns string|error {
        a2a:Task task = check self.agentClient->getTask({id: taskId});
        return summarize(task);
    }

    private isolated function cancelAgentTask(string taskId) returns string|error {
        a2a:Task task = check self.agentClient->cancelTask({id: taskId});
        return summarize(task);
    }

    private isolated function listAgentTasks() returns string|error {
        a2a:ListTasksResponse result = check self.agentClient->listTasks();
        if result.tasks.length() == 0 {
            return "No tasks found.";
        }
        string[] lines = from a2a:Task task in result.tasks select summarize(task);
        return string:'join("\n", ...lines);
    }

    private isolated function getAgentExtendedCard() returns string|error {
        a2a:AgentCard card = check self.agentClient->getExtendedAgentCard();
        string skills = string:'join(", ", ...from a2a:AgentSkill skill in card.skills select skill.id);
        return string `${card.name} extended card -- ${card.skills.length()} skill(s): ${skills}`;
    }

    private isolated function createAgentPushNotificationConfig(string taskId, string webhookUrl)
            returns string|error {
        a2a:TaskPushNotificationConfig created = check self.agentClient->createTaskPushNotificationConfig(
                {taskId, url: webhookUrl});
        string configId = created?.id ?: "(no id)";
        return string `Registered push notification config ${configId} for task ${taskId}.`;
    }

    private isolated function listAgentPushNotificationConfigs(string taskId) returns string|error {
        a2a:ListTaskPushNotificationConfigsResponse result =
            check self.agentClient->listTaskPushNotificationConfigs({taskId});
        a2a:TaskPushNotificationConfig[] configs = result.configs ?: [];
        if configs.length() == 0 {
            return string `No push notification configs registered for task ${taskId}.`;
        }
        string[] ids = from a2a:TaskPushNotificationConfig config in configs select config?.id ?: "(no id)";
        return string `Configs for task ${taskId}: ${string:'join(", ", ...ids)}`;
    }

    private isolated function deleteAgentPushNotificationConfig(string taskId, string configId)
            returns string|error {
        check self.agentClient->deleteTaskPushNotificationConfig({taskId, id: configId});
        return string `Deleted push notification config ${configId} from task ${taskId}.`;
    }

    # + continuation - Whether `initial` is the snapshot of a task that already
    #                  existed before this call. Such a task is not settled
    #                  just because it still shows the state it was in: that
    #                  state is from before the agent saw the new message.
    private isolated function pollUntilSettled(a2a:Task initial, boolean continuation = false)
            returns a2a:Task|error {
        a2a:Task task = initial;
        decimal elapsed = 0d;
        boolean first = true;
        while (!isSettled(task.status.state) || (continuation && unchangedSince(initial, task)))
                && elapsed < MAX_WAIT_SECONDS {
            if !first {
                runtime:sleep(POLL_INTERVAL_SECONDS);
                elapsed += POLL_INTERVAL_SECONDS;
            }
            first = false;
            task = check self.agentClient->getTask({id: task.id});
        }
        return task;
    }
}

// ---- shared helpers ----------------------------------------------------

final decimal MAX_WAIT_SECONDS = 20d;
final decimal POLL_INTERVAL_SECONDS = 0.5d;

# Builds the client for one agent. The card is passed rather than the URL,
# so the client uses the one already resolved at construction instead of
# fetching it again -- and a caller-supplied, signature-verified card stays
# the card actually used.
isolated function connect(a2a:AgentCard card, string? schemeName, string? secret,
        http:ClientConfiguration clientConfig) returns a2a:RestClient|error {
    if schemeName is string && secret is string {
        a2a:InMemoryCredentialStore store = new ({[schemeName]: secret});
        return new (card, clientConfig = clientConfig, credentials = store);
    }
    return new (card, clientConfig = clientConfig);
}

# Turns an agent's Card name into a tool-name suffix safe for the strict
# identifier pattern most model providers enforce on tool names (letters,
# digits and underscores only) -- "Trip Planner Agent" becomes
# "TripPlannerAgent". Two agents sharing a Card name still collide if both
# are placed in the same `ai:Agent.tools` array; this cannot be detected
# from inside one instance, which has no visibility into its siblings --
# give agents meaningfully distinct Card names, the same expectation
# ai:McpToolKit places on two identically-named McpToolKit variables.
isolated function toolSuffix(string agentName) returns string {
    string suffix = "";
    boolean startOfWord = true;
    foreach string:Char ch in agentName {
        int codePoint = ch.toCodePointInt();
        boolean isAlnum = (codePoint >= 65 && codePoint <= 90) || (codePoint >= 97 && codePoint <= 122)
            || (codePoint >= 48 && codePoint <= 57);
        if isAlnum {
            suffix += startOfWord ? ch.toUpperAscii() : ch;
            startOfWord = false;
        } else {
            startOfWord = true;
        }
    }
    return suffix.length() > 0 ? suffix : "Agent";
}

# Whether a task still looks exactly as it did in an earlier snapshot: same
# state and same status timestamp. Every transition writes a fresh timestamp, so
# an agent that asks its question a second time is still detected as having
# moved on, even though its state is INPUT_REQUIRED both times.
isolated function unchangedSince(a2a:Task before, a2a:Task now) returns boolean =>
    before.status.state == now.status.state && before.status?.timestamp == now.status?.timestamp;

# AUTH_REQUIRED and INPUT_REQUIRED count as settled: both mean the agent is
# waiting on the caller, so polling further would just burn the budget.
isolated function isSettled(a2a:TaskState state) returns boolean =>
    state == a2a:TASK_STATE_COMPLETED || state == a2a:TASK_STATE_FAILED
    || state == a2a:TASK_STATE_CANCELED || state == a2a:TASK_STATE_REJECTED
    || state == a2a:TASK_STATE_INPUT_REQUIRED || state == a2a:TASK_STATE_AUTH_REQUIRED;

isolated function partsText(a2a:Part[] parts) returns string {
    string[] texts = [];
    foreach a2a:Part part in parts {
        string? text = part?.text;
        if text is string {
            texts.push(text);
        }
    }
    return string:'join(" ", ...texts);
}

# An agent answers in an artifact when it finished and in a status message
# when it needs something, so both are checked -- reading only one would
# come back empty depending on how the request happened to resolve.
isolated function taskText(a2a:Task task) returns string {
    a2a:Artifact[] artifacts = task.artifacts ?: [];
    if artifacts.length() > 0 {
        return partsText(artifacts[artifacts.length() - 1].parts);
    }
    a2a:Message? statusMessage = task.status?.message;
    if statusMessage is a2a:Message {
        return partsText(statusMessage.parts);
    }
    return string `(no textual response -- task state: ${task.status.state})`;
}

# Carries the task id in every reply so the model can reuse it later for a
# status or cancel call without having to ask the user for it again.
isolated function summarize(a2a:Task task) returns string =>
    string `[${task.status.state}] ${taskText(task)} (task id: ${task.id})`;

# Collects a stream to completion. A tool call returns once, so the value
# of streaming here is capturing the intermediate updates rather than only
# the final state.
isolated function collectStream(stream<a2a:StreamResponse, a2a:Error?> events) returns string|error {
    string[] lines = [];
    while true {
        record {|a2a:StreamResponse value;|}|a2a:Error? next = events.next();
        if next is () {
            break;
        }
        if next is a2a:Error {
            lines.push(string `(stream ended with an error: ${next.message()})`);
            break;
        }
        a2a:StreamResponse event = next.value;
        if event is a2a:Task {
            lines.push(summarize(event));
        } else if event is a2a:Message {
            lines.push(partsText(event.parts));
        } else if event is a2a:TaskStatusUpdateEvent {
            lines.push(string `[${event.status.state}]`);
        } else {
            // event is now known (by elimination) to be a
            // TaskArtifactUpdateEvent, but StreamResponse's arms are all
            // open records, so the compiler can't prove that from a
            // sequence of `is` checks -- an explicit cast is required.
            a2a:TaskArtifactUpdateEvent artifactEvent = <a2a:TaskArtifactUpdateEvent>event;
            lines.push(string `artifact: ${partsText(artifactEvent.artifact.parts)}`);
        }
    }
    check events.close();
    return lines.length() == 0 ? "(no events received)" : string:'join("\n", ...lines);
}

isolated function schemaOf(map<json> properties, string[] required) returns map<json> =>
    {"type": "object", "properties": properties, "required": required};

isolated function taskIdSchema() returns map<json> =>
    schemaOf({"taskId": {"type": "string", "description": "The task id returned earlier."}}, ["taskId"]);
