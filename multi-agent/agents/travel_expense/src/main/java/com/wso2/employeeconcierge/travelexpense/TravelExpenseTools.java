package com.wso2.employeeconcierge.travelexpense;

import dev.langchain4j.agent.tool.Tool;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/** Real, in-memory expense-claim state the LLM agent's tool calls actually mutate. */
@ApplicationScoped
public class TravelExpenseTools {

  /** A real, mutable expense claim -- not a frozen string. */
  private static final class Claim {
    final String employeeName;
    final double amount;
    final String currency;
    final String description;
    final boolean requiresManagerApproval;
    volatile String status = "submitted"; // submitted | in_review | approved

    Claim(
        final String employeeName,
        final double amount,
        final String currency,
        final String description,
        final boolean requiresManagerApproval) {
      this.employeeName = employeeName;
      this.amount = amount;
      this.currency = currency;
      this.description = description;
      this.requiresManagerApproval = requiresManagerApproval;
    }
  }

  // A client-entertainment claim (the prompt already tells employees these
  // need manager approval) genuinely needs staged review; an ordinary
  // claim resolves fast, as a real one genuinely would. Real predicate on
  // the description, not left to the LLM to self-flag.
  private static final List<String> ENTERTAINMENT_KEYWORDS =
      List.of("entertain", "client dinner", "client lunch", "hospitality");

  private final AtomicInteger nextClaimId = new AtomicInteger(2000);
  private final Map<String, Claim> claims = new ConcurrentHashMap<>();

  static boolean isClientEntertainment(final String description) {
    String normalized = description.toLowerCase(Locale.ROOT);
    return ENTERTAINMENT_KEYWORDS.stream().anyMatch(normalized::contains);
  }

  // Not an LLM @Tool -- filing is executor-driven (same shape as Payroll's
  // correction filing): the LLM decides *that* a claim should be filed via
  // AgentResponse's structured fields, and the executor calls this
  // directly so it keeps the real claim id to drive a staged review for
  // client-entertainment claims specifically. See
  // TravelExpenseAgentExecutorProducer.
  String fileExpenseClaim(
      final String employeeName, final double amount, final String currency,
      final String description) {
    String id = "EX-" + nextClaimId.getAndIncrement();
    claims.put(
        id,
        new Claim(employeeName, amount, currency, description, isClientEntertainment(description)));
    return id;
  }

  boolean requiresManagerApproval(final String claimId) {
    Claim claim = claims.get(claimId);
    return claim != null && claim.requiresManagerApproval;
  }

  void setClaimStatus(final String claimId, final String status) {
    Claim claim = claims.get(claimId);
    if (claim != null) {
      claim.status = status;
    }
  }

  @Tool("Looks up the real, current status of a previously filed expense claim by its ID.")
  public String getClaimStatus(final String claimId) {
    Claim claim = claims.get(claimId);
    if (claim == null) {
      return "No expense claim found with ID " + claimId + ".";
    }
    return "Claim " + claimId + " for " + claim.employeeName + " (" + claim.amount + " "
        + claim.currency + " — " + claim.description + ") is " + claim.status + ".";
  }

  @Tool("Calculates a per-diem allowance for a trip of the given number of whole days and region. "
      + "Region must be one of: \"domestic\", \"asia_pacific\", or \"other\".")
  public String calculatePerDiem(final int days, final String region) {
    String normalizedRegion = region.toLowerCase(Locale.ROOT).trim();
    double dailyRate;
    String currency;
    if (normalizedRegion.contains("domestic")) {
      dailyRate = 6000;
      currency = "LKR";
    } else if (normalizedRegion.contains("asia")) {
      dailyRate = 60;
      currency = "USD";
    } else {
      dailyRate = 80;
      currency = "USD";
    }
    double total = dailyRate * days;
    return String.format(
        Locale.ROOT, "%d day(s) at %s %.2f/day = %s %.2f total", days, currency, dailyRate,
        currency, total);
  }
}
