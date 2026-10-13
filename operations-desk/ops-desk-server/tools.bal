import ballerina/ai;
import ballerina/lang.runtime;
import ballerina/random;

type AccessGrant record {|
    string grantId;
    string employee;
    string system;
    string status;
    string expiresOn;
|};

type ClaimDecision record {|
    string claimId;
    string status;
    string reason;
|};

type Incident record {|
    string id;
    string severity;
    string summary;
    string resolution;
|};

type OnboardingChecklist record {|
    string intern;
    string team;
    string startDate;
    string[] firstWeek;
|};

final readonly & map<Incident[]> incidentLog = {
    "payments": [
        {id: "INC-2041", severity: "SEV2", summary: "Payment callbacks delayed by 12 minutes", resolution: "Queue consumers scaled out, backlog cleared"}
    ],
    "gateway": [
        {id: "INC-2043", severity: "SEV1", summary: "Gateway returned 503 for 6% of requests", resolution: "Rolled back the 02:10 config change"},
        {id: "INC-2044", severity: "SEV3", summary: "Elevated latency in the EU region", resolution: "Recovered after the rollback"}
    ],
    "identity": []
};

# Grants an employee access to an internal system; provisioning takes a few seconds.
#
# + employee - Who needs the access
# + system - The system, for example "staging cloud project" or "vpn"
# + justification - The business reason for the access
# + return - The grant, or an error if provisioning failed
@ai:AgentTool
isolated function requestAccess(string employee, string system, string justification) returns AccessGrant|error {
    runtime:sleep(6);
    int number = check random:createIntInRange(1000, 9999);
    return {grantId: string `ACC-${number}`, employee, system, status: "PROVISIONED", expiresOn: "2027-03-31"};
}

# Reviews an expense claim; a receiptId is required for any claim over 200 USD.
#
# + employee - Who is claiming
# + amountUsd - The claimed amount in US dollars
# + category - What the money was spent on, for example "travel"
# + receiptId - The receipt reference; leave empty when the employee has none
# + return - The decision, or an error if the claim could not be reviewed
@ai:AgentTool
isolated function submitExpenseClaim(string employee, decimal amountUsd, string category, string receiptId = "")
        returns ClaimDecision|error {
    int number = check random:createIntInRange(1000, 9999);
    string claimId = string `EXP-${number}`;
    if amountUsd > 200d && receiptId == "" {
        return {claimId, status: "ON_HOLD", reason: "A receipt is required for claims over 200 USD"};
    }
    return {claimId, status: "APPROVED", reason: string `${category} claim for ${employee} is within policy`};
}

# Lists last night's incidents for one service: payments, gateway or identity.
#
# + serviceName - One of payments, gateway or identity
# + return - The incidents, or an error for an unknown service
@ai:AgentTool
isolated function getIncidentSummary(string serviceName) returns Incident[]|error {
    Incident[]? incidents = incidentLog[serviceName.toLowerAscii()];
    if incidents is () {
        return error(string `No incident log for service '${serviceName}'`);
    }
    return incidents;
}

# Builds the first-week checklist for a new intern.
#
# + intern - The intern's name
# + team - The team they join
# + startDate - Their first day
# + return - The checklist
@ai:AgentTool
isolated function getOnboardingChecklist(string intern, string team, string startDate) returns OnboardingChecklist {
    return {
        intern,
        team,
        startDate,
        firstWeek: [
            "Day 1: laptop, accounts and a walkthrough with your buddy",
            string `Day 2: meet the ${team} team and read its architecture notes`,
            "Day 3: set up the local build and run the test suite",
            "Day 4: pick up a starter issue with your mentor",
            "Day 5: show your first change in the team demo"
        ]
    };
}
