package com.wso2.employeeconcierge.travelexpense;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import java.util.List;
import org.a2aproject.sdk.server.PublicAgentCard;
import org.a2aproject.sdk.spec.AgentCapabilities;
import org.a2aproject.sdk.spec.AgentCard;
import org.a2aproject.sdk.spec.AgentInterface;
import org.a2aproject.sdk.spec.AgentSkill;
import org.a2aproject.sdk.spec.TransportProtocol;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Produces the public agent card for the WSO2 Travel & Expense Agent. */
@ApplicationScoped
public final class TravelExpenseAgentCardProducer {

  @Inject
  @ConfigProperty(name = "quarkus.http.port")
  private int httpPort;

  // What the agent card tells other clients to connect to — "localhost"
  // for local-process use, overridden to the Docker Compose service name
  // in containerized deployment.
  @Inject
  @ConfigProperty(name = "a2a.advertised-host", defaultValue = "localhost")
  private String advertisedHost;

  @Produces
  @PublicAgentCard
  public AgentCard agentCard() {
    return AgentCard.builder()
        .name("Travel & Expense Agent")
        .description("WSO2 Travel & Expense — expense claims and travel policy questions.")
        .version("0.1.0")
        .capabilities(
            AgentCapabilities.builder()
                .streaming(false)
                .pushNotifications(true)
                .extendedAgentCard(false)
                .build())
        .defaultInputModes(List.of("text"))
        .defaultOutputModes(List.of("text"))
        .skills(
            List.of(
                AgentSkill.builder()
                    .id("file-expense-claim")
                    .name("File an expense claim")
                    .description("Files a travel or expense reimbursement claim for review.")
                    .tags(List.of("expense", "travel"))
                    .examples(List.of("I need to claim LKR 12000 for a client dinner in Colombo"))
                    .build(),
                AgentSkill.builder()
                    .id("expense-status")
                    .name("Check expense claim status")
                    .description("Answers travel/expense policy questions and claim status checks.")
                    .tags(List.of("expense", "faq"))
                    .examples(List.of("what's the per-diem rate for a Singapore trip?"))
                    .build()))
        .supportedInterfaces(
            List.of(new AgentInterface(TransportProtocol.HTTP_JSON.asString(), "http://" + advertisedHost + ":" + httpPort)))
        .build();
  }
}
