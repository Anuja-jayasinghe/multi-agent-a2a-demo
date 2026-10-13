// The real ballerina/ai Agent (routing decision layer) on a real
// Anthropic model, wired with the five real tool functions from
// agent_tools.bal. Code-complete now, but actually invoking it means
// invoking the real model, so full routing verification (does it pick
// the right tool for a given request) happens in Phase 9 once a real
// ANTHROPIC_API_KEY is supplied — see agent_tools_test.bal for what's
// verified without one.
import ballerina/ai;
import ballerina/os;
import ballerinax/ai.anthropic;

// Falls back to this configurable when ANTHROPIC_API_KEY isn't in the
// process's environment -- e.g. launched via WSO2 Integrator: BI's
// Run/Debug, which spawns `bal run` directly without sourcing this
// repo's .env the way scripts/start-agents.sh and start-all.sh do. Set
// via orchestrator/Config.toml (gitignored, dev-time only), Ballerina's
// own standard mechanism for exactly this.
configurable string anthropicApiKey = "";

final string resolvedAnthropicApiKey = os:getEnv("ANTHROPIC_API_KEY") != ""
    ? os:getEnv("ANTHROPIC_API_KEY")
    : anthropicApiKey;

final ai:ModelProvider anthropicModel = check new anthropic:ModelProvider(
    resolvedAnthropicApiKey,
    anthropic:CLAUDE_SONNET_4_5
);

final ai:Agent concierge = check new (
    systemPrompt = {
        role: "WSO2 Employee Concierge",
        instructions: string `You help WSO2 employees by delegating their requests to the right
            real internal agent and relaying its real answer back. You don't have the agents'
            names or capabilities memorized — call discoverAgents once, near the start of a
            conversation (not before every request), to see each real agent's name,
            description, and skills, and use that to decide which one fits a given request. If
            none of them fit, say so instead of guessing.

            delegateToAgent sends a *new* request, in natural language, to one agent by its
            exact name from discoverAgents — a fresh reservation, ticket, claim, or question.
            To cancel, check the status of, or ask about an *existing* request you already have
            a task id for from earlier in this conversation, you MUST call cancelAgentTask or
            getAgentTaskStatus directly with that agent name and task id — never send a
            cancel/status request as natural-language text through delegateToAgent instead;
            the target agent has no way to act on a cancel/status request phrased as a plain
            message, only through those two dedicated tools. listAgentTasks lists everything an
            agent has seen, by name, with no task id needed. Two hard rules for all four of
            these tools, both real and both equally wrong to break:
            (1) A status/cancel/list question about an existing task ALWAYS requires a fresh,
            real call to the matching tool in the turn it's asked — even if you already checked
            that exact task earlier in this same conversation. Earlier knowledge, however
            recent, never substitutes for a real call; answering from memory instead of calling
            the tool is not a shortcut, it is a wrong answer, because the real state may have
            changed since you last checked.
            (2) Call each tool at most once per sub-request per turn. If a request needs two
            different tools (e.g. cancel one task and check another), call each once — never
            call the same tool twice for what is really one question.

            Reservations, tickets, corrections, and claims are tied to a real employee name.
            If you don't already have it from this conversation, ask for it before making the
            request, then reuse it for later requests without asking again. Read-only
            questions don't need a name. These agents do track and will reveal who made a
            request when asked — never assume that's private and refuse on your own.

            Some requests take real time to finish — delegateToAgent may return while the
            task is still SUBMITTED or WORKING rather than complete. Relay that real status
            and the task id to the employee in plain language (never say it's finished when
            it isn't), and reuse that same task id with getAgentTaskStatus if they later ask
            whether it's done.

            No proactive notifications ("let me know when...") — only respond to what's asked.`
    },
    model = anthropicModel,
    // ai:Agent's own default maxIter is max(tools.length(), 10) -- down to
    // 5 real generic delegation tools instead of 20 named ones specifically
    // to give the real, confirmed non-deterministic redundant-tool-call
    // tendency documented in GitHub issue #24 less room to run; re-verified
    // after this rewrite (see the issue for the real before/after numbers).
    // Kept an explicit, tested cap rather than relying on the auto-scaled
    // default, since the issue reproduced even with a single tool and
    // isn't fully eliminated by tool count alone. getAgentExtendedCard is a
    // 6th, deliberately narrow tool on top of those 5 -- its own doc
    // comment scopes it to explicit extended/admin-card requests only, so
    // it shouldn't add to normal delegation's redundant-call surface.
    maxIter = 10,
    tools = [discoverAgents, delegateToAgent, cancelAgentTask, getAgentTaskStatus, listAgentTasks, getAgentExtendedCard]
);
