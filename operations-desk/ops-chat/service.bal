import ballerina/ai;
import ballerina/http;

service on new ai:Listener(8090) {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        string answer = check assistant.run(request.message, request.sessionId);
        return {message: answer};
    }
}

// chat() { curl -s -X POST localhost:8090/chat -H 'Content-Type: application/json' -d "{\"sessionId\":\"demo\",\"message\":\"$1\"}"; echo; }
