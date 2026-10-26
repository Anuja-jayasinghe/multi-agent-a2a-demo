import ballerina/ai;
import ballerina/http;

listener ai:Listener conciergeChatListener = new (listenOn = check http:getDefaultListener());

service /concierge on conciergeChatListener {
    resource function post chat(@http:Payload ai:ChatReqMessage request) returns ai:ChatRespMessage|error {
        string stringResult = check concierge.run(request.message, request.sessionId);
        return {message: stringResult};
    }
}
