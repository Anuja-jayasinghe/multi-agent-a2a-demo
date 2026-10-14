import ballerina/ai;
import ballerina/http;

service on new ai:Listener(8090) {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        string answer = check assistant.run(request.message, request.sessionId);
        return {message: answer};
    }
}
