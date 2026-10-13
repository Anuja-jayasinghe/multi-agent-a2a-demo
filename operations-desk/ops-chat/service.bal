import ballerina/ai;
import ballerina/http;

listener http:Listener chatEndpoint = new (8090);

service on new ai:Listener(chatEndpoint) {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        string answer = check assistant.run(request.message, request.sessionId);
        return {message: answer};
    }
}
