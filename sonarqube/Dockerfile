# docker build -t local-github-runner
FROM sonarqube:community

USER root

# Install plugins
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /opt/sonarqube/extensions/plugins && \
    curl -fSL https://github.com/gretard/sonar-sql-plugin/releases/download/1.4.0/sonar-sql-plugin-1.4.0.jar -o /opt/sonarqube/extensions/plugins/sonar-sql-plugin.jar && \
    curl -fSL https://github.com/gjd6640/sonar-text-plugin/releases/download/v3.0.0/sonar-txt-plugin-2.0.0.jar -o /opt/sonarqube/extensions/plugins/sonar-txt-plugin.jar && \
    chown -R 1000:0 /opt/sonarqube/extensions/plugins && \
    chmod -R 644 /opt/sonarqube/extensions/plugins && \
    find /opt/sonarqube/extensions/plugins -type d -exec chmod 755 {} \;

RUN chown -R 1000:0 /opt/sonarqube/data && \
    chmod -R 755 /opt/sonarqube/data

USER 1000