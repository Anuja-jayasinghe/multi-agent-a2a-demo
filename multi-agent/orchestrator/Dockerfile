# Run orchestrator/prepare-docker-build.sh first — ballerina/a2a isn't
# published to Central, and Docker's build context can't reach outside
# this directory to pull it from the local Ballerina repository directly.
FROM ballerina/ballerina:2201.13.5 AS build
WORKDIR /app

COPY --chown=ballerina:ballerina .docker-local-repo/a2a /home/ballerina/.ballerina/repositories/local/bala/ballerina/a2a

COPY --chown=ballerina:ballerina Ballerina.toml Dependencies.toml ./
COPY --chown=ballerina:ballerina *.bal ./
RUN bal build --sticky

FROM ballerina/ballerina:2201.13.5
WORKDIR /app
COPY --chown=ballerina:ballerina --from=build /app/target/bin/orchestrator.jar ./

EXPOSE 9090 8090
CMD ["bal", "run", "orchestrator.jar"]
