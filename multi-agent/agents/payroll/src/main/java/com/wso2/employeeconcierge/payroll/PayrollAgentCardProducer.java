package com.wso2.employeeconcierge.payroll;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.a2aproject.sdk.server.ExtendedAgentCard;
import org.a2aproject.sdk.server.PublicAgentCard;
import org.a2aproject.sdk.spec.AgentCapabilities;
import org.a2aproject.sdk.spec.AgentCard;
import org.a2aproject.sdk.spec.AgentInterface;
import org.a2aproject.sdk.spec.AgentSkill;
import org.a2aproject.sdk.spec.HTTPAuthSecurityScheme;
import org.a2aproject.sdk.spec.SecurityRequirement;
import org.a2aproject.sdk.spec.TransportProtocol;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Produces the public and admin-only extended agent cards for the WSO2
 * Payroll Agent. See AdminOnlyExtendedCardInterceptor for how the
 * extended card is actually gated — the SDK's own GetExtendedAgentCard
 * handling here is a fixed bean lookup, not per-caller.
 */
@ApplicationScoped
public final class PayrollAgentCardProducer {

  @Inject
  @ConfigProperty(name = "quarkus.grpc.server.port")
  private int grpcPort;

  // What the agent card tells other clients to connect to — "localhost"
  // for local-process use, overridden to the Docker Compose service name
  // (e.g. "payroll") in containerized deployment, since the server bind
  // address (quarkus.http.host / quarkus.grpc.server.host, separately
  // set to 0.0.0.0 there) isn't a valid address for another container to
  // dial back into.
  @Inject
  @ConfigProperty(name = "a2a.advertised-host", defaultValue = "localhost")
  private String advertisedHost;

  private static final List<AgentSkill> PUBLIC_SKILLS = List.of(
      AgentSkill.builder()
          .id("payslip-correction")
          .name("Request a payslip correction")
          .description("Files a payslip correction request for review.")
          .tags(List.of("payroll", "payslip"))
          .examples(List.of("my payslip shows the wrong tax deduction"))
          .build(),
      AgentSkill.builder()
          .id("payroll-lookup")
          .name("Answer payroll questions")
          .description("Answers common payroll questions — pay cycle, deductions.")
          .tags(List.of("payroll", "faq"))
          .examples(List.of("when is the next pay date?"))
          .build());

  // The name a client resolves via securitySchemes to learn this actually
  // means "send an HTTP Bearer token" -- matches PeopleOperations'
  // equivalent (bearer-staff) in shape, distinct in name since the two
  // credentials are not interchangeable. AdminOnlyExtendedCardInterceptor
  // is what actually enforces this; declaring it here only makes it
  // discoverable, per spec section 7.3 -- a caller reading the card
  // before ever authenticating already knows what to present.
  private static final String ADMIN_SCHEME = "bearer-admin";

  private static final AgentSkill ADMIN_SKILL = AgentSkill.builder()
      .id("adjust-other-employee-payroll")
      .name("Adjust another employee's payroll")
      .description("Admin-only: directly adjusts a payroll record for an employee other than the caller.")
      .tags(List.of("payroll", "admin"))
      .examples(List.of("apply a one-off bonus of LKR 5000 to employee E-1042"))
      .build();

  @Produces
  @PublicAgentCard
  public AgentCard agentCard() {
    return baseBuilder("Payroll Agent",
            "WSO2 Payroll — payslip corrections and payroll lookups.")
        .skills(PUBLIC_SKILLS)
        .build();
  }

  @Produces
  @ExtendedAgentCard
  public AgentCard extendedAgentCard() {
    List<AgentSkill> skills = new ArrayList<>(PUBLIC_SKILLS);
    skills.add(ADMIN_SKILL);
    return baseBuilder("Payroll Agent (Admin)",
            "WSO2 Payroll — payslip corrections, payroll lookups, and admin-only payroll adjustment.")
        .skills(skills)
        .build();
  }

  private AgentCard.Builder baseBuilder(final String name, final String description) {
    return AgentCard.builder()
        .name(name)
        .description(description)
        .version("0.1.0")
        .capabilities(
            AgentCapabilities.builder()
                .streaming(false)
                .pushNotifications(true)
                .extendedAgentCard(true)
                .build())
        .defaultInputModes(List.of("text"))
        .defaultOutputModes(List.of("text"))
        .supportedInterfaces(
            List.of(new AgentInterface(TransportProtocol.GRPC.asString(), advertisedHost + ":" + grpcPort)))
        .securitySchemes(Map.of(ADMIN_SCHEME,
            HTTPAuthSecurityScheme.builder()
                .scheme("Bearer")
                .description("Admin bearer token. Required for the extended card and "
                    + "adjust-other-employee-payroll.")
                .build()))
        .securityRequirements(List.of(
            SecurityRequirement.builder().scheme(ADMIN_SCHEME, List.of()).build()));
  }
}
