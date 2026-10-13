package com.wso2.employeeconcierge.payroll;

import dev.langchain4j.agent.tool.Tool;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.YearMonth;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/** Real, in-memory payroll state the LLM agent's tool calls actually mutate. */
@ApplicationScoped
public class PayrollTools {

  /** A real, mutable payslip correction request -- not a frozen string. */
  public static final class Correction {
    final String employeeName;
    final String description;
    volatile String status = "submitted"; // submitted | in_review | approved

    Correction(final String employeeName, final String description) {
      this.employeeName = employeeName;
      this.description = description;
    }
  }

  private final AtomicInteger nextCorrectionId = new AtomicInteger(1000);
  private final AtomicInteger nextAdjustmentId = new AtomicInteger(9000);
  private final Map<String, Correction> corrections = new ConcurrentHashMap<>();

  // Not an LLM @Tool -- filing is executor-driven (same shape as Parking's
  // reservation creation): the LLM decides *that* a correction should be
  // filed via AgentResponse's structured fields, and the executor calls
  // this directly so it keeps the real correction id to drive the staged
  // review that follows. See PayrollAgentExecutorProducer.
  String fileCorrectionRequest(final String employeeName, final String description) {
    String id = "PC-" + nextCorrectionId.getAndIncrement();
    corrections.put(id, new Correction(employeeName, description));
    return id;
  }

  void setCorrectionStatus(final String correctionId, final String status) {
    Correction correction = corrections.get(correctionId);
    if (correction != null) {
      correction.status = status;
    }
  }

  @Tool("Looks up the real, current status of a previously filed payslip correction request by its ID.")
  public String getCorrectionStatus(final String correctionId) {
    Correction correction = corrections.get(correctionId);
    if (correction == null) {
      return "No correction request found with ID " + correctionId + ".";
    }
    return "Correction request " + correctionId + " for " + correction.employeeName
        + " (" + correction.description + ") is " + correction.status + ".";
  }

  // Fictional-but-plausible figures, consistent every time for the same
  // employee/month pair -- no real payroll data or figures.
  @Tool("Looks up an employee's last 3 months of pay history: gross pay, deductions, net pay.")
  public String getPayHistory(final String employeeName) {
    StringBuilder sb = new StringBuilder("Pay history for ").append(employeeName).append(":\n");
    YearMonth month = YearMonth.now();
    for (int i = 0; i < 3; i++) {
      YearMonth payMonth = month.minusMonths(i);
      sb.append("- ").append(payMonth)
          .append(": gross LKR 450,000, deductions LKR 62,000, net LKR 388,000\n");
    }
    return sb.toString();
  }

  @Tool("Files a real request for a tax document (e.g. annual tax certificate) for an employee for "
      + "a given year. Returns a request reference.")
  public String requestTaxDocument(final String employeeName, final String year) {
    String reference = "TAXDOC-" + employeeName.replaceAll("\\s+", "").toUpperCase() + "-" + year;
    return "Tax document request " + reference + " filed for " + employeeName + " (" + year
        + "). It will be available on the HR portal within 3 working days.";
  }

  /** Real, in-memory record of admin payroll adjustments actually applied. */
  private final Map<String, String> adjustments = new ConcurrentHashMap<>();

  @Tool("Adjusts another employee's payroll figure. Admin-only: refuses unless the caller "
      + "presented a valid admin token.")
  public String adjustOtherEmployeePayroll(
      final String employeeName, final String field, final String newValue) {
    // The real gate. The extended card only controls whether this skill is
    // *advertised*; spec section 13.1 requires the server to authorize
    // every request, so visibility must not be what protects it. A caller
    // who already knows this skill exists reaches here regardless, which
    // is exactly the case this check exists for.
    if (!AdminOnlyExtendedCardInterceptor.isAdminAuthenticated()) {
      return "DENIED: adjusting another employee's payroll is admin-only, and this request "
          + "carried no valid admin token. No change was made.";
    }
    String reference = "ADJ-" + (nextAdjustmentId.getAndIncrement());
    adjustments.put(reference, employeeName + ":" + field + "=" + newValue);
    return "Adjustment " + reference + " applied: " + field + " set to " + newValue + " for "
        + employeeName + ".";
  }

  /** How many adjustments were actually applied -- used by verification. */
  public int appliedAdjustmentCount() {
    return adjustments.size();
  }
}
