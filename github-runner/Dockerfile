# Build Go tools from source with a current toolchain: the released binaries
# are compiled with old Go/x/net versions that Trivy flags. Runs on the build
# host's platform and cross-compiles for the target (no emulation).
FROM --platform=$BUILDPLATFORM golang:1.27.3-trixie AS gotools
ARG TARGETOS
ARG TARGETARCH
ARG YQ_VERSION=v4.54.1
ARG OTEL_CLI_VERSION=v0.4.5
ENV CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH}
RUN set -eux; \
  git clone --depth 1 --branch "${YQ_VERSION}" https://github.com/mikefarah/yq /src/yq; \
  cd /src/yq; \
  go get golang.org/x/net@latest && go mod tidy; \
  go build -trimpath -ldflags="-s -w" -o /out/yq .; \
  git clone --depth 1 --branch "${OTEL_CLI_VERSION}" https://github.com/equinix-labs/otel-cli /src/otel-cli; \
  cd /src/otel-cli; \
  go get -u ./... && go mod tidy; \
  go build -trimpath -ldflags="-s -w" -o /out/otel-cli .

# Base image
FROM eclipse-temurin:21.0.13_9-jre-resolute

# Set build arguments
ARG TARGETARCH
ARG RUNNER_VERSION="2.338.2"
ARG DEBIAN_FRONTEND=noninteractive

# Debug output
RUN echo "🐳 Building for architecture: ${TARGETARCH}" && \
    echo "📦 Installing GitHub Actions Runner version: ${RUNNER_VERSION}"

# Install required packages (Java comes from the temurin base image)
RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip zip curl python3 python3-venv \
    git jq ca-certificates file \
    dumb-init sudo && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=gotools /out/yq /out/otel-cli /usr/local/bin/


# Sonar Scanner, docker user, and the GitHub Actions runner (TARGETARCH arm64/amd64 -> arm64/x64)
RUN set -eux; \
  curl -fL -o sonar-scanner.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-8.3.1.16491.zip; \
  unzip -q sonar-scanner.zip -d /usr/local; \
  mv /usr/local/sonar-scanner-* /usr/local/sonar-scanner; \
  chmod +x /usr/local/sonar-scanner/bin/sonar-scanner; \
  ln -s /usr/local/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner; \
  rm sonar-scanner.zip; \
  # docker must be UID 1000 (sonar-init writes the token file as 1000:1000);
  # Ubuntu 23.04+ images ship a default 'ubuntu' user with that UID
  userdel -r ubuntu 2>/dev/null || true; \
  useradd -m -u 1000 docker; \
  echo "docker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers; \
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
  # npm is bundled with the runner's node but never used; it carries most JS CVEs
  rm -rf /home/docker/actions-runner/externals/node*/lib/node_modules/npm \
         /home/docker/actions-runner/externals/node*/bin/npm /home/docker/actions-runner/externals/node*/bin/npx; \
  chown -R docker /home/docker/actions-runner

# Install Snowflake CLI and SQLFluff into a venv (system Python is PEP 668 managed)
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv "$VIRTUAL_ENV" && \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --upgrade pip setuptools && \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --upgrade 'snowflake-cli>=3.18.0' pyyaml sqlfluff && \
    "$VIRTUAL_ENV/bin/pip" uninstall -y pip && \
    chown -R docker "$VIRTUAL_ENV"

# Local CI support (local-ci/run.sh): node on PATH for JS actions under act,
# plus act and the docker CLI so this image can also serve the local-ci service
ARG ACT_VERSION=0.2.94
ARG DOCKER_CLI_VERSION=29.9.2
RUN set -eux; \
  ln -sf /home/docker/actions-runner/externals/node24/bin/node /usr/local/bin/node; \
  if [ "${TARGETARCH}" = "arm64" ]; then ACT_ARCH=arm64; DOCKER_ARCH=aarch64; else ACT_ARCH=x86_64; DOCKER_ARCH=x86_64; fi; \
  curl -fsSL "https://github.com/nektos/act/releases/download/v${ACT_VERSION}/act_Linux_${ACT_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin act; \
  curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_CLI_VERSION}.tgz" \
    | tar -xz -C /usr/local/bin --strip-components=1 docker/docker

# Set environment PATH
ENV PATH="/opt/venv/bin:/usr/local/sonar-scanner/bin:/usr/local/bin:${PATH}"

# Copy helper scripts
COPY *.sh /usr/local/bin/
COPY *.py /usr/local/bin/
COPY *.sqltest /usr/local/bin/
COPY *.cfg /usr/local/bin/
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