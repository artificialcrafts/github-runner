#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RUNNER_ENV_FILE:-docker/envs/clocktopus.env}"
COMPOSE="docker-compose -f docker/docker-compose.yml"

if [[ ! -f "${ROOT_DIR}/${ENV_FILE}" ]]; then
  echo "Env file ${ROOT_DIR}/${ENV_FILE} not found. Set RUNNER_ENV_FILE or create it." >&2
  exit 1
fi

# Export all vars defined in the env file (RUNNER_TOKEN stays blank, PAT is optional)
set -a
source "${ROOT_DIR}/${ENV_FILE}"
set +a

export RUNNER_ENV_FILE="${ENV_FILE}"

case "${1:-}" in
  start)
    ${COMPOSE} up -d
    ;;
  stop)
    ${COMPOSE} down --remove-orphans
    ;;
  restart)
    ${COMPOSE} down --remove-orphans
    ${COMPOSE} up -d
    ;;
  logs)
    shift
    ${COMPOSE} logs "${@:-github-runner}"
    ;;
  build)
    ${COMPOSE} build --no-cache github-runner
    ;;
  *)
    cat <<'USAGE'
Usage: scripts/runner.sh <command> [args]

Commands:
  start     Start the self-hosted runner
  stop      Stop the runner and remove containers/networks
  restart   Stop then start the runner
  logs      Tail docker-compose logs (default service: github-runner)
  build     Rebuild the runner image (forced no-cache)

Environment variables:
  RUNNER_ENV_FILE   Path (relative to docker/) to the env file (default envs/clocktopus.env)
USAGE
    exit 1
    ;;
esac
