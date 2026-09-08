package com.wso2.employeeconcierge.payroll;

import io.grpc.Context;
import io.grpc.Contexts;
import io.grpc.Metadata;
import io.grpc.ServerCall;
import io.grpc.ServerCallHandler;
import io.grpc.ServerInterceptor;
import io.grpc.Status;
import io.quarkus.grpc.GlobalInterceptor;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.Optional;
import org.a2aproject.sdk.grpc.A2AServiceGrpc;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Gates only the GetExtendedAgentCard RPC behind a real bearer-token check.
 *
 * <p>The a2a-java gRPC reference module (1.1.0.Final) has no per-request
 * extended-card modifier hook the way the Python SDK does — its
 * getExtendedAgentCard() is a fixed, context-free bean lookup (confirmed
 * by reading GrpcHandler/QuarkusGrpcHandler source). So rather than
 * downgrading the card's content per caller like PeopleOperations does,
 * this rejects the RPC outright for anyone without the admin token — a
 * different, still-genuine answer to the same requirement, working within
 * what this SDK version actually offers. Every other RPC on the service is
 * untouched: this interceptor only inspects the one method name it cares
 * about and calls next.startCall for everything else.
 */
@ApplicationScoped
@GlobalInterceptor
public class AdminOnlyExtendedCardInterceptor implements ServerInterceptor {

  private static final Metadata.Key<String> AUTHORIZATION =
      Metadata.Key.of("authorization", Metadata.ASCII_STRING_MARSHALLER);

  /**
   * Whether the call being served presented a valid admin token.
   *
   * <p>Published for every RPC, not just the extended-card one, so an
   * admin-only <em>action</em> can be authorized where it actually runs.
   * Hiding a skill from the unauthenticated card only controls whether it
   * is advertised; anyone who knows the skill exists can still ask for it,
   * and spec section 13.1 requires the server to authorize every request.
   * A gRPC Context key rather than a field because one interceptor
   * instance serves concurrent calls.
   */
  public static final Context.Key<Boolean> ADMIN_AUTHENTICATED =
      Context.key("payroll-admin-authenticated");

  // Optional<String>, not a plain String with an empty defaultValue --
  // tried that first, and MicroProfile Config treats an empty default the
  // same as no default at all (confirmed empirically: both a bare
  // ${PAYROLL_ADMIN_TOKEN:} expression in application.properties and
  // @ConfigProperty(defaultValue = "") threw the identical "Failed to
  // load config value" at startup the moment PAYROLL_ADMIN_TOKEN was
  // genuinely unset -- not deny access, the whole app failing to boot).
  // Optional<T> injection is the spec's actual mechanism for a property
  // that may legitimately be absent; it resolves to empty rather than
  // failing, and every call site below already treats "no token
  // configured" and "empty token" identically, so collapsing them via
  // orElse("") costs nothing.
  @ConfigProperty(name = "payroll.admin-token")
  Optional<String> adminToken;

  /** Whether the call currently being served is admin-authenticated. */
  public static boolean isAdminAuthenticated() {
    return Boolean.TRUE.equals(ADMIN_AUTHENTICATED.get());
  }

  @Override
  public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
      final ServerCall<ReqT, RespT> call, final Metadata headers,
      final ServerCallHandler<ReqT, RespT> next) {
    String token = adminToken.orElse("");
    String expected = "Bearer " + token;
    String actual = headers.get(AUTHORIZATION);
    boolean admin = !token.isEmpty() && actual != null && actual.equals(expected);

    String fullMethod = call.getMethodDescriptor().getFullMethodName();
    String extendedCardMethod = A2AServiceGrpc.getGetExtendedAgentCardMethod().getFullMethodName();
    if (fullMethod.equals(extendedCardMethod) && !admin) {
      call.close(Status.PERMISSION_DENIED.withDescription(
          "GetExtendedAgentCard requires a valid admin bearer token"), new Metadata());
      return new ServerCall.Listener<>() { };
    }

    // Every other RPC proceeds regardless -- the public skills really are
    // public. What changes is that the answer is carried forward, so
    // adjustOtherEmployeePayroll can refuse on its own rather than relying
    // on the caller never having heard of it.
    Context ctx = Context.current().withValue(ADMIN_AUTHENTICATED, admin);
    return Contexts.interceptCall(ctx, call, headers, next);
  }
}
