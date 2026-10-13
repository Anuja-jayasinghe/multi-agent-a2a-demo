package com.wso2.employeeconcierge.travelexpense;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.a2aproject.sdk.server.agentexecution.AgentExecutor;
import org.a2aproject.sdk.server.agentexecution.RequestContext;
import org.a2aproject.sdk.server.tasks.AgentEmitter;
import org.a2aproject.sdk.spec.A2AError;
import org.a2aproject.sdk.spec.Part;
import org.a2aproject.sdk.spec.Task;
import org.a2aproject.sdk.spec.TaskNotCancelableError;
import org.a2aproject.sdk.spec.TextPart;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Wires the real langchain4j-anthropic TravelExpenseAgent into a genuine A2A task lifecycle. */
@ApplicationScoped
public final class TravelExpenseAgentExecutorProducer {

  @Inject private TravelExpenseAgent travelExpenseAgent;

  @Inject private TravelExpenseTools travelExpenseTools;

  // Real, staged wall-clock delay per review step for a client-entertainment
  // claim specifically -- an ordinary claim skips this entirely and
  // resolves fast, as a real one genuinely would (same catalog-vs-approval
  // split idea as DigiOps' hardware provisioning). Read once at process
  // start; an env override (TRAVELEXPENSE_REVIEW_STEP_DELAY_SECONDS) only
  // affects agent processes *started* after it's set -- see
  // orchestrator/README.md for why that matters.
  @Inject
  @ConfigProperty(name = "travelexpense.review.step-delay-seconds", defaultValue = "200")
  private int reviewStepDelaySeconds;

  @Produces
  public AgentExecutor agentExecutor() {
    return new TravelExpenseAgentExecutor(travelExpenseAgent, travelExpenseTools, reviewStepDelaySeconds);
  }

  private static final class TravelExpenseAgentExecutor implements AgentExecutor {

    private static final List<String> REVIEW_STEPS =
        List.of("Routing to manager for approval...", "Verifying against travel policy...");

    private final TravelExpenseAgent agent;
    private final TravelExpenseTools tools;
    private final int reviewStepDelaySeconds;

    // taskId -> latch, counted down by cancel() to interrupt a pending
    // claim review between staged steps. In-memory only, matches the
    // Python agents' asyncio.Event cancel-signal pattern.
    private final Map<String, CountDownLatch> cancelSignals = new ConcurrentHashMap<>();

    TravelExpenseAgentExecutor(
        final TravelExpenseAgent agentInstance,
        final TravelExpenseTools toolsInstance,
        final int reviewStepDelaySecondsValue) {
      this.agent = agentInstance;
      this.tools = toolsInstance;
      this.reviewStepDelaySeconds = reviewStepDelaySecondsValue;
    }

    @Override
    public void execute(final RequestContext context, final AgentEmitter emitter) throws A2AError {
      if (context.getTask() == null) {
        emitter.submit();
      }
      emitter.startWork();

      final String userInput = context.getUserInput();
      // memoryId keyed by the real A2A contextId, not taskId -- same
      // per-conversation granularity the three Python agents already get
      // for free from their own framework's session store. A real
      // Anthropic call: the model itself decides, via its own tool
      // calling, whether this is a status check (getClaimStatus), a
      // per-diem calculation (calculatePerDiem), a plain policy FAQ
      // answered from the system prompt's reference facts, or a new
      // expense claim -- the last one is reported back via structured
      // fields, not a tool call, so this executor (not the LLM) files it
      // for real and decides whether it needs staged review below.
      final AgentResponse response = agent.respond(context.getContextId(), userInput);
      final List<Part<?>> parts = List.of(new TextPart(response.message(), null));

      if ("input-required".equals(response.status())) {
        // Genuinely pause and wait for the missing info -- this used to
        // always force-complete here even for a clarifying question, so
        // the task lied about being done. A follow-up message for the
        // same taskId/contextId resumes normally now that real memory
        // (above) actually carries the conversation forward.
        emitter.requiresInput(emitter.newAgentMessage(parts, null));
        return;
      }
      if ("failed".equals(response.status())) {
        emitter.fail(emitter.newAgentMessage(parts, null));
        return;
      }
      if (hasText(response.claimEmployeeName())
          && response.claimAmount() != null
          && response.claimAmount() > 0
          && hasText(response.claimCurrency())
          && hasText(response.claimDescription())) {
        fileAndResolveClaim(context, emitter, response);
        return;
      }
      emitter.addArtifact(parts, null, null, null);
      emitter.complete();
    }

    private void fileAndResolveClaim(
        final RequestContext context, final AgentEmitter emitter, final AgentResponse response)
        throws A2AError {
      final String claimId =
          tools.fileExpenseClaim(
              response.claimEmployeeName(), response.claimAmount(), response.claimCurrency(),
              response.claimDescription());

      if (!tools.requiresManagerApproval(claimId)) {
        tools.setClaimStatus(claimId, "approved");
        final String fastMessage =
            "Claim " + claimId + " for " + response.claimEmployeeName() + " has been filed and "
                + "approved.";
        final List<Part<?>> fastParts = List.of(new TextPart(fastMessage, null));
        emitter.addArtifact(fastParts, null, null, null);
        emitter.complete(emitter.newAgentMessage(fastParts, null));
        return;
      }

      // Client entertainment: a real staged manager-approval review, same
      // cancel-signal shape as Payroll's correction review.
      final String taskId = context.getTaskId();
      final CountDownLatch cancelSignal = new CountDownLatch(1);
      cancelSignals.put(taskId, cancelSignal);
      try {
        tools.setClaimStatus(claimId, "in_review");
        for (final String step : REVIEW_STEPS) {
          emitter.startWork(
              emitter.newAgentMessage(
                  List.of(new TextPart(step + " (claim " + claimId + ")", null)), null));
          final boolean canceled = cancelSignal.await(reviewStepDelaySeconds, TimeUnit.SECONDS);
          if (canceled) {
            return; // cancel() already handled the task-state transition
          }
        }
        tools.setClaimStatus(claimId, "approved");
        final String finalMessage =
            "Claim " + claimId + " for " + response.claimEmployeeName() + " (client "
                + "entertainment) has been reviewed by a manager and approved.";
        final List<Part<?>> finalParts = List.of(new TextPart(finalMessage, null));
        emitter.addArtifact(finalParts, null, null, null);
        emitter.complete(emitter.newAgentMessage(finalParts, null));
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        emitter.fail();
      } finally {
        cancelSignals.remove(taskId);
      }
    }

    // Structured-output records don't reliably leave an unset optional
    // field null -- langchain4j's JSON-schema-backed extraction can fill
    // an unset String with "" (confirmed for Payroll's equivalent
    // fields). Checking for real, non-blank text is what actually
    // distinguishes "this field means something" from "unset".
    private static boolean hasText(final String value) {
      return value != null && !value.isBlank();
    }

    @Override
    public void cancel(final RequestContext context, final AgentEmitter emitter) throws A2AError {
      final Task task = context.getTask();
      if (task == null || task.status().state().isFinal()) {
        throw new TaskNotCancelableError();
      }
      final CountDownLatch signal = cancelSignals.get(context.getTaskId());
      emitter.cancel();
      if (signal != null) {
        signal.countDown();
      }
    }
  }
}
