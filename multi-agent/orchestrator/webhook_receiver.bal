// The push-notification webhook receiver the orchestrator hosts. Agents
// with pushNotifications capability (Parking, Payroll, Travel & Expense)
// are registered with a config pointing here; this logs every real
// delivery so Phase 6's verification script can assert it actually
// happened, not just that the config CRUD succeeded.
import ballerina/http;
import ballerina/log;
import ballerina/time;

public const string WEBHOOK_PATH = "/webhooks/push";

public type NotificationReceipt record {|
    string taskId;
    string? state;
    string token;
    string receivedAt;
|};

isolated NotificationReceipt[] receivedNotifications = [];

isolated function recordNotification(NotificationReceipt receipt) {
    lock {
        receivedNotifications.push(receipt.clone());
    }
}

// The two SDKs in this demo shape the push-notification body differently
// even though both are spec-compliant: a2a-java sends the Task/event flat
// (JsonUtil.toJsonStreamingEvent), while a2a-python wraps it in a
// StreamResponse oneof envelope (MessageToDict(to_stream_response(event))),
// e.g. {"task": {...}} or {"statusUpdate": {...}}. Unwrap the envelope
// first, if present, then extract fields from whatever's left.
isolated function unwrapEnvelope(map<json> payload) returns map<json> {
    foreach string key in ["task", "statusUpdate", "artifactUpdate", "message"] {
        json? inner = payload[key];
        if inner is map<json> {
            return inner;
        }
    }
    return payload;
}

isolated function extractTaskId(json payload) returns string? {
    if payload is map<json> {
        map<json> body = unwrapEnvelope(payload);
        json? id = body["id"];
        if id is string {
            return id;
        }
        json? taskId = body["taskId"];
        if taskId is string {
            return taskId;
        }
    }
    return ();
}

isolated function extractState(json payload) returns string? {
    if payload is map<json> {
        map<json> body = unwrapEnvelope(payload);
        json? status = body["status"];
        if status is map<json> {
            json? state = status["state"];
            if state is string {
                return state;
            }
        }
    }
    return ();
}

service on new http:Listener(9090) {

    resource function post webhooks/push(http:Request req) returns http:Ok|http:BadRequest {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return <http:BadRequest>{body: "expected a JSON push-notification payload"};
        }
        string? taskId = extractTaskId(payload);
        if taskId is () {
            return <http:BadRequest>{body: "payload has neither 'id' nor 'taskId'"};
        }
        string|http:HeaderNotFoundError tokenHeader = req.getHeader("X-A2A-Notification-Token");
        string token = tokenHeader is string ? tokenHeader : "";
        NotificationReceipt receipt = {
            taskId,
            state: extractState(payload),
            token,
            receivedAt: time:utcToString(time:utcNow())
        };
        recordNotification(receipt);
        log:printInfo("received push notification", taskId = taskId, state = receipt.state);
        return <http:Ok>{};
    }

    resource function get webhooks/received() returns NotificationReceipt[] {
        lock {
            return receivedNotifications.clone();
        }
    }
}

