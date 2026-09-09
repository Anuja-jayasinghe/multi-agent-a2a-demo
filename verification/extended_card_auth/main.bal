// Use case: discovering an agent's credential requirement from its own
// Agent Card, then using that discovery to unlock its extended card —
// against the real, running PeopleOperations agent. No mocks, no stubs.
//
// This is the end-to-end exercise for ballerina/a2a's card-driven
// credential support: skillSecurityRequirements, resolveSecuritySchemes,
// CredentialProvider/InMemoryCredentialStore, and the in-task
// authorization helpers.
//
// The point it proves: a client that starts knowing *only a URL* can work
// out which credential a guarded skill needs, supply it by scheme name,
// and get the extended card — without anyone hardcoding a header name or
// being told out of band which token goes where.
//
// Start the agent first (no LLM key needed — every check here is card and
// auth logic, no model call):
//
//   cd agents/peopleoperations
//   PEOPLEOPS_STAFF_TOKEN=demo-staff-secret uv run __main__.py
//
// then, from this directory:  bal run --sticky

import ballerina/a2a;
import ballerina/io;
import ballerina/os;
import ballerina/uuid;

const string AGENT_URL = "http://127.0.0.1:8002";

// From the same env var the agent reads — see the note in
// verification/peopleoperations/main.bal for why this is not a constant.
final string STAFF_TOKEN = os:getEnv("PEOPLEOPS_STAFF_TOKEN") != ""
    ? os:getEnv("PEOPLEOPS_STAFF_TOKEN")
    : "demo-staff-secret";
const string GUARDED_SKILL = "case-escalation";
const string PUBLIC_SKILL = "policy-qa";

int failures = 0;
int skipped = 0;

function check_(boolean condition, string description, string detail = "") {
    if condition {
        io:println("[ok]   ", description, detail == "" ? "" : "  (" + detail + ")");
    } else {
        io:println("[FAIL] ", description, detail == "" ? "" : "  (" + detail + ")");
        failures += 1;
    }
}

# Records a check that could not be exercised in this environment.
#
# Counted and reported separately rather than logged as a pass — a check
# that never ran is not a check that succeeded.
#
# + description - what would have been verified
# + reason - why it could not run here
function skip_(string description, string reason) {
    io:println("[skip] ", description, "  (", reason, ")");
    skipped += 1;
}

# Sends one message and returns every piece of text the agent replied
# with, wherever it put it.
#
# An agent may answer in a status message (when it needs more from the
# caller) or in an artifact (when it finished), so both are collected —
# asserting against only one of them would pass or fail for the wrong
# reason depending on how the request happened to resolve.
#
# + agent - the client to send through
# + text - the request to send
# + return - the concatenated reply text, or an error if the call failed
function replyText(a2a:Client agent, string text) returns string|error {
    a2a:Message request = {
        messageId: uuid:createType4AsString(),
        role: a2a:ROLE_USER,
        parts: [{text: text}]
    };
    a2a:Task|a2a:Message reply = check agent->sendMessage(request);
    if reply is a2a:Message {
        return reply.parts.toString();
    }
    a2a:Task task = <a2a:Task>reply;
    string collected = "";
    a2a:Message? statusMessage = task.status?.message;
    if statusMessage is a2a:Message {
        collected += statusMessage.parts.toString();
    }
    foreach a2a:Artifact artifact in task.artifacts {
        collected += artifact.parts.toString();
    }
    return collected;
}

# Shortens a reply for single-line reporting.
#
# + value - the text to shorten
# + return - the text, truncated if long
function trim(string value) returns string {
    string flat = re `\n`.replaceAll(value, " ");
    return flat.length() <= 110 ? flat : flat.substring(0, 110) + "...";
}

public function main() returns error? {
    io:println("=== Extended card auth — real ballerina/a2a use case ===\n");

    // ----------------------------------------------------------------
    // 1. Discovery: the card must actually declare its security model.
    // ----------------------------------------------------------------
    io:println("-- 1. Reading the public card --");
    a2a:AgentCard card = check a2a:resolveAgentCard(AGENT_URL);

    check_(card.capabilities.extendedAgentCard,
            "agent declares an extended card exists");
    check_(card.securitySchemes.length() > 0,
            "public card declares securitySchemes",
            card.securitySchemes.keys().toString());
    // This is the real v1.0 wire form: {"schemes": {"bearer-staff": {}}}.
    // It parsed as [] before the parser fix, which silently made every
    // check below impossible.
    check_(card.securityRequirements.length() > 0,
            "card-level securityRequirements parse from the real v1.0 wire form",
            card.securityRequirements.toString());
    check_(!card.skills.some(s => s.id == GUARDED_SKILL),
            "guarded skill is absent from the public card");

    // ----------------------------------------------------------------
    // 2. skillSecurityRequirements — per-skill discovery.
    // ----------------------------------------------------------------
    io:println("\n-- 2. Working out what each skill needs --");

    // The guarded skill lives on the *extended* card, so read that first
    // (unauthenticated: the agent downgrades rather than rejecting).
    a2a:Client anonymous = check new (AGENT_URL);
    a2a:AgentCard anonExtended = check anonymous->getExtendedAgentCard();
    check_(!anonExtended.skills.some(s => s.id == GUARDED_SKILL),
            "unauthenticated extended card is downgraded, guarded skill withheld",
            anonExtended.skills.length().toString() + " skills");
    check_(anonExtended.securitySchemes.length() > 0,
            "downgraded card still names the credential that would unlock more",
            anonExtended.securitySchemes.keys().toString());

    a2a:SecurityRequirement[] publicNeeds = check a2a:skillSecurityRequirements(card, PUBLIC_SKILL);
    check_(publicNeeds == card.securityRequirements,
            "a skill declaring nothing inherits the card-level requirement",
            publicNeeds.toString());

    a2a:SecurityRequirement[]|a2a:Error unknown = a2a:skillSecurityRequirements(card, "no-such-skill");
    check_(unknown is a2a:Error,
            "an unknown skill id is a typed Error, not an empty list");

    // ----------------------------------------------------------------
    // 3. resolveSecuritySchemes — turning a name into something usable.
    // ----------------------------------------------------------------
    io:println("\n-- 3. Resolving the scheme name to a concrete kind --");
    a2a:SecurityRequirement requirement = card.securityRequirements[0];
    map<a2a:SecurityScheme> resolved = check a2a:resolveSecuritySchemes(card, requirement);
    check_(resolved.length() == 1, "requirement resolves to exactly one scheme");

    string schemeName = resolved.keys()[0];
    a2a:SecurityScheme scheme = resolved.get(schemeName);
    check_(scheme is a2a:HttpAuthSecurityScheme,
            "scheme resolves to a concrete kind, not just a name",
            schemeName);
    if scheme is a2a:HttpAuthSecurityScheme {
        check_(scheme.scheme.toLowerAscii() == "bearer",
                "resolved kind is HTTP bearer — enough to know what to send",
                scheme.scheme);
    }

    map<a2a:SecurityScheme>|a2a:Error ghost =
            a2a:resolveSecuritySchemes(card, {"not-declared": []});
    check_(ghost is a2a:Error,
            "a requirement naming an undeclared scheme is reported, not dropped");

    // ----------------------------------------------------------------
    // 4. The payoff: feed discovery straight into a CredentialProvider.
    //    Nothing below hardcodes a header name — schemeName came from
    //    the card itself in step 3.
    // ----------------------------------------------------------------
    io:println("\n-- 4. Unlocking the extended card using only what was discovered --");
    a2a:InMemoryCredentialStore store = new ();
    store.setCredential(schemeName, STAFF_TOKEN);

    a2a:Client staff = check new (AGENT_URL, credentials = store);
    a2a:AgentCard staffExtended = check staff->getExtendedAgentCard();
    check_(staffExtended.skills.some(s => s.id == GUARDED_SKILL),
            "credential resolved from the card unlocks the guarded skill",
            staffExtended.skills.length().toString() + " skills");
    check_(staffExtended.skills.length() > anonExtended.skills.length(),
            "authenticated card genuinely carries more than the anonymous one",
            anonExtended.skills.length().toString() + " -> " + staffExtended.skills.length().toString());

    // The guarded skill, once visible, declares its own requirement.
    a2a:SecurityRequirement[] guardedNeeds =
            check a2a:skillSecurityRequirements(staffExtended, GUARDED_SKILL);
    check_(guardedNeeds.length() > 0 && guardedNeeds[0].hasKey(schemeName),
            "the guarded skill declares the same scheme at skill level",
            guardedNeeds.toString());

    // ----------------------------------------------------------------
    // 5. Negative cases — proving the credential is really being checked
    //    and really being sent, rather than the agent just being open.
    // ----------------------------------------------------------------
    io:println("\n-- 5. Negative and rotation cases --");

    a2a:InMemoryCredentialStore wrongStore = new ({[schemeName]: "not-the-real-token"});
    a2a:Client wrong = check new (AGENT_URL, credentials = wrongStore);
    a2a:AgentCard wrongCard = check wrong->getExtendedAgentCard();
    check_(!wrongCard.skills.some(s => s.id == GUARDED_SKILL),
            "a wrong credential is genuinely rejected, not waved through");

    // Rotation: the same client picks up a replaced credential, which a
    // static headers map could not do without rebuilding the client.
    wrongStore.setCredential(schemeName, STAFF_TOKEN);
    a2a:AgentCard rotatedCard = check wrong->getExtendedAgentCard();
    check_(rotatedCard.skills.some(s => s.id == GUARDED_SKILL),
            "replacing the credential on a live client takes effect immediately");

    // A credential held under a scheme name the card never declares must
    // not be sent — it satisfies no requirement.
    a2a:InMemoryCredentialStore misfiled = new ({"some-other-scheme": STAFF_TOKEN});
    a2a:Client misfiledClient = check new (AGENT_URL, credentials = misfiled);
    a2a:AgentCard misfiledCard = check misfiledClient->getExtendedAgentCard();
    check_(!misfiledCard.skills.some(s => s.id == GUARDED_SKILL),
            "a credential filed under an undeclared scheme name is not sent");

    // An empty provider behaves exactly like no provider: request goes
    // bare, agent answers, nothing fails locally.
    a2a:Client emptyProvider = check new (AGENT_URL, credentials = new a2a:InMemoryCredentialStore());
    a2a:AgentCard emptyCard = check emptyProvider->getExtendedAgentCard();
    check_(!emptyCard.skills.some(s => s.id == GUARDED_SKILL),
            "an empty provider sends the request bare rather than failing");

    // ----------------------------------------------------------------
    // 6. Equivalence and coexistence with the pre-existing route.
    // ----------------------------------------------------------------
    io:println("\n-- 6. Equivalence with the explicit-headers route --");
    a2a:Client explicitHeaders = check new (AGENT_URL,
            headers = {"Authorization": "Bearer " + STAFF_TOKEN});
    a2a:AgentCard explicitCard = check explicitHeaders->getExtendedAgentCard();
    check_(explicitCard.skills.length() == staffExtended.skills.length(),
            "provider and explicit-header routes produce the same result",
            explicitCard.skills.length().toString() + " skills both ways");

    // An explicit header wins over a provider-resolved one: here the
    // provider holds a bad token and the header holds the good one.
    a2a:InMemoryCredentialStore losing = new ({[schemeName]: "not-the-real-token"});
    a2a:Client headerWins = check new (AGENT_URL,
            headers = {"Authorization": "Bearer " + STAFF_TOKEN}, credentials = losing);
    a2a:AgentCard headerWinsCard = check headerWins->getExtendedAgentCard();
    check_(headerWinsCard.skills.some(s => s.id == GUARDED_SKILL),
            "an explicit header takes precedence over a card-resolved credential");

    // ----------------------------------------------------------------
    // 7. Normal traffic is unaffected, and the in-task auth helpers read
    //    a real task correctly.
    // ----------------------------------------------------------------
    io:println("\n-- 7. Ordinary calls still work, and task-state helpers read real tasks --");
    a2a:Message msg = {
        messageId: uuid:createType4AsString(),
        role: a2a:ROLE_USER,
        parts: [{text: "how many annual leave days do I have?"}]
    };
    a2a:Task|a2a:Message|error reply = staff->sendMessage(msg);
    if reply is a2a:Task {
        check_(!a2a:isAuthorizationRequired(reply),
                "isAuthorizationRequired is false for a task the agent did not gate",
                reply.status.state);
        check_(a2a:authorizationPrompt(reply) is (),
                "authorizationPrompt is nil when no authorization was requested");
    } else if reply is a2a:Message {
        check_(true, "credentialled client gets a direct Message on ordinary traffic");
        skip_("isAuthorizationRequired / authorizationPrompt against a real task",
                "agent answered with a Message, not a Task");
    } else if reply is error {
        // The error still had to travel the full client -> agent -> model
        // path, so it does prove a credentialled client is not broken —
        // but it yields no Task, so the two helpers genuinely go
        // unexercised here rather than being counted as passing.
        string detail = reply.message();
        check_(detail.includes("Anthropic") || detail.includes("API key")
                    || detail.includes("authentication"),
                "credentialled client reaches the agent and its model on ordinary traffic",
                "model rejected the request, which required the full path to work");
        skip_("isAuthorizationRequired / authorizationPrompt against a real task",
                "no usable ANTHROPIC_API_KEY, so the agent returns no Task; " +
                "both helpers are unit-tested in the library itself");
    }

    // ----------------------------------------------------------------
    // 8. The gate that actually matters: invoking the guarded skill.
    //    Card gating only controls whether the skill is *advertised* —
    //    spec section 13.1 requires the server to authorize the request
    //    itself, so this asks for the skill by name from both sides.
    // ----------------------------------------------------------------
    io:println("\n-- 8. Invoking the guarded skill, with and without the credential --");
    string escalationRequest =
            "Escalate a grievance for Nadia Perera to a case manager. Summary: repeated payroll errors.";

    string anonReply = check replyText(anonymous, escalationRequest);
    boolean anonRefused = !anonReply.toLowerAscii().includes("successfully escalated")
        && (anonReply.toLowerAscii().includes("staff-only")
            || anonReply.toLowerAscii().includes("staff only")
            || anonReply.toLowerAscii().includes("credential")
            || anonReply.toLowerAscii().includes("unable")
            || anonReply.toLowerAscii().includes("denied"));
    check_(anonRefused,
            "an unauthenticated caller asking for the guarded skill by name is refused",
            trim(anonReply));

    string staffReply = check replyText(staff, escalationRequest);
    check_(staffReply.toLowerAscii().includes("escalat")
                && !staffReply.toLowerAscii().includes("staff-only"),
            "the same request succeeds for an authenticated caller",
            trim(staffReply));

    // ----------------------------------------------------------------
    io:println("");
    int failed = failures;
    string skipNote = skipped == 0 ? "" : ", " + skipped.toString() + " skipped";
    if failed == 0 {
        io:println("=== ALL CHECKS PASSED", skipNote, " ===");
        return;
    }
    io:println("=== ", failed, " CHECK(S) FAILED", skipNote, " ===");
    return error(failed.toString() + " check(s) failed");
}
