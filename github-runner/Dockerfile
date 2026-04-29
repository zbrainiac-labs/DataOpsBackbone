# Base image
FROM eclipse-temurin:21-jre-jammy

# Set build arguments
ARG TARGETARCH
ARG RUNNER_VERSION="2.327.1"
ARG DEBIAN_FRONTEND=noninteractive

# Debug output
RUN echo "🐳 Building for architecture: ${TARGETARCH}" && \
    echo "📦 Installing GitHub Actions Runner version: ${RUNNER_VERSION}"

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip zip curl openjdk-21-jre python3 python3-pip python3-dev \
    build-essential git jq ca-certificates libffi-dev libssl-dev file \
    dumb-init sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


# Install Sonar Scanner
RUN curl -L -o sonar-scanner.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006.zip && \
    unzip sonar-scanner.zip -d /usr/local && \
    mv /usr/local/sonar-scanner-* /usr/local/sonar-scanner && \
    chmod +x /usr/local/sonar-scanner/bin/sonar-scanner && \
    ln -s /usr/local/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner && \
    rm sonar-scanner.zip

# Create docker user
RUN useradd -m docker

# Map TARGETARCH for GitHub Actions runner (arm64 → arm)
RUN set -eux; \
  if [ "${TARGETARCH}" = "arm64" ]; then \
    RUNNER_ARCH=arm64; \
  elif [ "${TARGETARCH}" = "amd64" ]; then \
    RUNNER_ARCH=x64; \
  else \
    RUNNER_ARCH=${TARGETARCH}; \
  fi; \
  echo "TARGETARCH=${TARGETARCH}"; \
  echo "RUNNER_ARCH=${RUNNER_ARCH}"; \
  curl -fL -o actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"; \
  mkdir -p /home/docker/actions-runner; \
  tar -xzf actions-runner.tar.gz -C /home/docker/actions-runner; \
  rm actions-runner.tar.gz; \
  /home/docker/actions-runner/bin/installdependencies.sh; \
  chown -R docker /home/docker/actions-runner

RUN echo "docker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Snowflake CLI
RUN pip install --no-cache-dir snowflake-cli pyyaml

# Set environment PATH
ENV PATH="/usr/local/sonar-scanner/bin:/usr/local/bin:${PATH}"

# Copy helper scripts
COPY *.sh /usr/local/bin/
COPY *.sqltest /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

COPY unitth.jar /usr/local/bin/
COPY unitth.properties /usr/local/bin/

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /usr/share/nginx/html && chown -R docker:docker /usr/share/nginx/html

RUN mkdir -p /usr/local/bin/unit-report && chown -R docker:docker /usr/local/bin/unit-report

# Set user and working directory
USER docker
WORKDIR /home/docker/actions-runner

RUN mkdir -p "/home/docker/sql-unit-reports"

# Entrypoint command
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]