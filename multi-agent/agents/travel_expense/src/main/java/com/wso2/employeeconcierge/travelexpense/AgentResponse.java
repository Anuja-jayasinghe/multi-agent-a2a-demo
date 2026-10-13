package com.wso2.employeeconcierge.travelexpense;

/**
 * Structured reply the LLM must produce, mirroring the status-driven pattern the three Python
 * agents already use (google-adk's output_schema / LangGraph's response_format) -- lets the
 * executor genuinely branch (complete vs. requiresInput vs. fail) instead of always completing.
 *
 * @param message reply text for the employee -- the only thing they ever see
 * @param status one of "completed", "input-required", "failed"
 * @param claimEmployeeName set only when the employee clearly wants to file a NEW expense claim
 *     and has given their real name -- null otherwise. The executor (not a tool call) files the
 *     real claim and drives its staged review when needed, mirroring how Payroll's executor
 *     files real correction requests from structured fields like these.
 * @param claimAmount the real numeric amount, set only alongside claimEmployeeName
 * @param claimCurrency the real currency code (e.g. "USD", "LKR"), set only alongside
 *     claimEmployeeName
 * @param claimDescription what the expense was for, set only alongside claimEmployeeName
 */
public record AgentResponse(
    String message,
    String status,
    String claimEmployeeName,
    Double claimAmount,
    String claimCurrency,
    String claimDescription) {}
