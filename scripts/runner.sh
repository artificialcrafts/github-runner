#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="docker-compose -f docker/docker-compose.yml"

ENV_FILE_INPUT="${RUNNER_ENV_FILE:-envs/clocktopus.env}"

case "${ENV_FILE_INPUT}" in
  /*)
    HOST_ENV_PATH="${ENV_FILE_INPUT}"
    COMPOSE_ENV_PATH="${ENV_FILE_INPUT}"
    ;;
  docker/*)
    HOST_ENV_PATH="${ROOT_DIR}/${ENV_FILE_INPUT}"
    COMPOSE_ENV_PATH="${ENV_FILE_INPUT#docker/}"
    ;;
  *)
    HOST_ENV_PATH="${ROOT_DIR}/docker/${ENV_FILE_INPUT}"
    COMPOSE_ENV_PATH="${ENV_FILE_INPUT}"
    ;;
esac

if [[ ! -f "${HOST_ENV_PATH}" ]]; then
  echo "Env file ${HOST_ENV_PATH} not found. Set RUNNER_ENV_FILE or create it." >&2
  exit 1
fi

# Export all vars defined in the env file (RUNNER_TOKEN stays blank, PAT is optional)
set -a
source "${HOST_ENV_PATH}"
set +a

export RUNNER_ENV_FILE="${COMPOSE_ENV_PATH}"

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
  RUNNER_ENV_FILE   Env file (default envs/clocktopus.env). Accepts paths like
                    "envs/foo.env", "docker/envs/foo.env", or an absolute path.
USAGE
    exit 1
    ;;
esac
