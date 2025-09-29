# Docker image for a self-hosted GitHub Actions runner
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_VERSION=2.317.0 \
    RUNNER_HOME=/runner \
    RUNNER_WORKDIR=/runner/_work

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        libicu70 \
        unzip \
        tar \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --home-dir ${RUNNER_HOME} runner \
    && mkdir -p ${RUNNER_HOME} ${RUNNER_WORKDIR}

WORKDIR ${RUNNER_HOME}

RUN curl -sSL https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    -o actions-runner.tar.gz \
    && tar -xzf actions-runner.tar.gz \
    && rm actions-runner.tar.gz \
    && ./bin/installdependencies.sh

RUN chown -R runner:runner ${RUNNER_HOME}

USER runner
COPY --chown=runner:runner scripts/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

ENTRYPOINT ["/runner/entrypoint.sh"]
