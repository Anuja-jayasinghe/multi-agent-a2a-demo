// Presentation demo: real concurrent, independently-tracked tasks.
//
// The A2A v1.0.0 spec has no formal "queue" — TaskState has no QUEUED
// value, and no agent in this demo does admission control. What's real
// is simpler and just as demo-worthy: multiple genuinely simultaneous
// tasks against the same agent, each tracked, pollable, and cancelable
// independently by its own task id. This fires N real onboarding
// requests at PeopleOperations concurrently (start/wait futures, same
// pattern already proven at 20x in verification/chaos_test/main.bal),
// then proves independence via listTasks, cancelTask on just one, and
// getTask polling the rest through to real completion.
//
// Start PeopleOperations first (or all five via scripts/start-agents.sh),
// with a real ANTHROPIC_API_KEY in .env, then run this script from this
// directory: bal run --sticky
import ballerina/a2a;
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/uuid;

const string AGENT_URL = "http://127.0.0.1:8002";

final string[] NAMES = [
    "Kasun Silva", "Nadeesha Perera", "Priyanka Fernando", "Sanjaya Perera",
    "Dilani Jayawardena"
];

public function main() returns error? {
    a2a:Client agent = check new (AGENT_URL);

    io:println("=== firing ", NAMES.length(), " real onboarding requests concurrently ===");
    future<a2a:Task|a2a:Message|error>[] futures = [];
    foreach string name in NAMES {
        a2a:Message msg = {
            messageId: uuid:createType4AsString(),
            role: a2a:ROLE_USER,
            parts: [{text: "onboard " + name + " as a new hire"}]
        };
        future<a2a:Task|a2a:Message|error> f = start agent->sendMessage(msg, config = {returnImmediately: true});
        futures.push(f);
    }

    string[] taskIds = [];
    foreach int i in 0 ..< futures.length() {
        a2a:Task|a2a:Message|error r = wait futures[i];
        if r is a2a:Task {
            taskIds.push(r.id);
            io:println("  ", NAMES[i], " -> task ", r.id, " (", r.status.state, ")");
        } else {
            io:println("  [FAIL] ", NAMES[i], ": expected a Task, got ", r);
        }
    }

    io:println("\n=== listTasks proves all ", taskIds.length(), " are independently tracked, not one shared job ===");
    a2a:ListTasksResult listed = check agent->listTasks();
    string[] knownIds = from a2a:Task t in listed.tasks select t.id;
    int foundCount = taskIds.filter(id => knownIds.indexOf(id) is int).length();
    io:println(foundCount, "/", taskIds.length(), " of this run's own task ids confirmed present ",
            "(agent reports ", listed.tasks.length(), " known task(s) total, including earlier runs)");

    if taskIds.length() == 0 {
        return error("no real tasks were created — nothing left to demo");
    }

    io:println("\n=== cancel the first one mid-flight -- the other ", taskIds.length() - 1, " keep going, untouched ===");
    string canceledId = taskIds[0];
    a2a:Task canceled = check agent->cancelTask(canceledId);
    io:println(NAMES[0], "'s task (", canceledId, ") -> ", canceled.status.state);

    io:println("\n=== poll the rest independently through to real completion ===");
    foreach int i in 1 ..< taskIds.length() {
        string tid = taskIds[i];
        a2a:Task t = check agent->getTask(tid);
        int polls = 0;
        while t.status.state != a2a:TASK_STATE_COMPLETED
                && t.status.state != a2a:TASK_STATE_FAILED
                && polls < 60 {
            runtime:sleep(1);
            t = check agent->getTask(tid);
            polls += 1;
        }
        io:println(NAMES[i], "'s task (", tid, ") -> ", t.status.state, " (", polls, " polls)");
    }

    io:println("\n=== DONE: ", taskIds.length(), " real concurrent tasks — created, listed, ",
            "one canceled mid-flight, the rest completed independently, all by task id ===");
}
