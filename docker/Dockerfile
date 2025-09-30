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
        openssh-client \
        unzip \
        tar \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-26.1.4.tgz \
    -o /tmp/docker-cli.tgz \
    && tar -xzf /tmp/docker-cli.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && chmod +x /usr/local/bin/docker \
    && rm -rf /tmp/docker /tmp/docker-cli.tgz

RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL https://github.com/docker/buildx/releases/download/v0.15.1/buildx-v0.15.1.linux-amd64 \
        -o /usr/local/lib/docker/cli-plugins/docker-buildx \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx \
    && curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
        -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

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
