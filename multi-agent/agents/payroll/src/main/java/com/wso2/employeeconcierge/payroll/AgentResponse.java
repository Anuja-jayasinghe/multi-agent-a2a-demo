package com.wso2.employeeconcierge.payroll;

/**
 * Structured reply the LLM must produce, mirroring the status-driven pattern the three Python
 * agents already use (google-adk's output_schema / LangGraph's response_format) -- lets the
 * executor genuinely branch (complete vs. requiresInput vs. fail) instead of always completing.
 *
 * @param message reply text for the employee -- the only thing they ever see
 * @param status one of "completed", "input-required", "failed"
 * @param correctionEmployeeName set only when the employee clearly wants to file a NEW payslip
 *     correction and has given their real name -- null otherwise. The executor (not a tool call)
 *     files the real correction request and drives its staged review, mirroring how Parking's
 *     executor -- not the LLM -- creates the real reservation from structured fields like these.
 * @param correctionDescription what's wrong with the payslip, set only alongside
 *     correctionEmployeeName
 */
public record AgentResponse(
    String message,
    String status,
    String correctionEmployeeName,
    String correctionDescription) {}
