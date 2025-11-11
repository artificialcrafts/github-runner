#!/usr/bin/env bash
set -euo pipefail
export DOCKER_BUILDKIT=1

SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ "${SCRIPT_PATH}" != /* ]]; then
  SCRIPT_PATH="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)/$(basename "${SCRIPT_PATH}")"
fi
ROOT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")/.." && pwd)"
COMPOSE="docker-compose -f docker/docker-compose.yml"

# Parse flags: allow -e/--env/-env to select env file
ENV_FILE_INPUT_DEFAULT="${RUNNER_ENV_FILE:-envs/clocktopus.env}"
ENV_FILE_INPUT="${ENV_FILE_INPUT_DEFAULT}"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--env|-env)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for $1 (expected an env filename/path)" >&2
        exit 1
      fi
      ENV_FILE_INPUT="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}"

# If a bare filename is provided (no slash), assume docker/envs/<name>.env
if [[ "${ENV_FILE_INPUT}" != */* ]]; then
  ENV_FILE_INPUT="envs/${ENV_FILE_INPUT}"
fi

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

set -a
source "${HOST_ENV_PATH}"
set +a

## Determine a unique Compose project name
# Priority: explicit COMPOSE_PROJECT_NAME > APP_NAME > RUNNER_NAME > env file basename
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"
if [[ -z "${PROJECT_NAME}" ]]; then
  if [[ -n "${APP_NAME:-}" ]]; then
    PROJECT_NAME="${APP_NAME}"
  elif [[ -n "${RUNNER_NAME:-}" ]]; then
    PROJECT_NAME="${RUNNER_NAME}"
  else
    PROJECT_NAME="$(basename "${ENV_FILE_INPUT%.*}")"
  fi
fi
# Sanitize to docker-compose friendly (lowercase, keep a-z0-9_-) and default if empty
PROJECT_NAME="$(echo "${PROJECT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
if [[ -z "${PROJECT_NAME}" ]]; then
  PROJECT_NAME="runner"
fi
export COMPOSE_PROJECT_NAME="${PROJECT_NAME}"
# Rebuild COMPOSE with the project name so operations don't collide across envs
COMPOSE="docker-compose -p ${COMPOSE_PROJECT_NAME} -f docker/docker-compose.yml"

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

Options:
  -e, --env, -env <file>   Env file to use. Accepts bare filenames like
                           "clocktopus.env" (resolved to docker/envs/clocktopus.env),
                           relative paths like "envs/foo.env" or "docker/envs/foo.env",
                           or an absolute path.

Environment variables:
  RUNNER_ENV_FILE   Env file (default envs/clocktopus.env). Accepts paths like
                    "envs/foo.env", "docker/envs/foo.env", or an absolute path.

Examples:
  scripts/runner.sh start -env clocktopus.env
  scripts/runner.sh logs --env envs/playground.env github-runner
USAGE
    exit 1
    ;;
esac
