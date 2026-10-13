FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

COPY pom.xml ./
COPY src ./src
RUN mvn -q -B -DskipTests -Dquarkus.analytics.disabled=true package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/quarkus-app/ ./

EXPOSE 8004
ENTRYPOINT ["java", "-jar", "quarkus-run.jar"]
