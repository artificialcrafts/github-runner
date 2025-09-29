#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  if [[ -n "${RUNNER_CFG_TOKEN:-}" ]]; then
    echo "Removing runner..."
    ./config.sh remove --token "${RUNNER_CFG_TOKEN}" --unattended || true
  else
    ./config.sh remove --unattended || true
  fi
}

handle_signal() {
  echo "Signal received, shutting down..."
  cleanup
  exit 0
}

trap handle_signal SIGINT SIGTERM

if [[ -z "${RUNNER_URL:-}" ]]; then
  echo "RUNNER_URL is required (e.g. https://github.com/org/repo)" >&2
  exit 1
fi

if [[ -z "${RUNNER_TOKEN:-}" ]]; then
  echo "RUNNER_TOKEN is required. Generate a registration token from GitHub" >&2
  exit 1
fi

RUNNER_NAME=${RUNNER_NAME:-$(hostname)}
RUNNER_WORKDIR=${RUNNER_WORKDIR:-_work}
RUNNER_LABELS=${RUNNER_LABELS:-self-hosted,linux}
RUNNER_CFG_TOKEN=${RUNNER_TOKEN}

CONFIG_ARGS=(
  "--url" "${RUNNER_URL}"
  "--token" "${RUNNER_TOKEN}"
  "--name" "${RUNNER_NAME}"
  "--work" "${RUNNER_WORKDIR}"
  "--labels" "${RUNNER_LABELS}"
  "--runnergroup" "${RUNNER_GROUP:-Default}"
  "--unattended"
  "--replace"
)

if [[ -n "${RUNNER_EPHEMERAL:-}" ]]; then
  CONFIG_ARGS+=("--ephemeral")
fi

./config.sh "${CONFIG_ARGS[@]}"

unset RUNNER_TOKEN

./run.sh --startuptype service &
RUNNER_PID=$!
wait ${RUNNER_PID}
EXIT_CODE=$?
cleanup
exit ${EXIT_CODE}
