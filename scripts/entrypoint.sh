#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  local removal_token="${RUNNER_CFG_TOKEN:-}"

  if [[ -z "${removal_token}" && -n "${GITHUB_PAT:-}" ]]; then
    removal_token=$(request_github_token "remove") || true
  fi

  if [[ -n "${removal_token}" ]]; then
    echo "Removing runner..."
    ./config.sh remove --token "${removal_token}" --unattended || true
  else
    echo "Runner removal skipped (no token available)" >&2
  fi
}

handle_signal() {
  echo "Signal received, shutting down..."
  cleanup
  exit 0
}

request_github_token() {
  local token_type="$1"
  if [[ -z "${GITHUB_PAT:-}" ]]; then
    echo "GITHUB_PAT missing; cannot request ${token_type} token" >&2
    return 1
  fi

  local endpoint base_url response token
  base_url=${GITHUB_API_URL:-https://api.github.com}

  case "${RUNNER_SCOPE}" in
    org)
      endpoint="${base_url}/orgs/${GITHUB_OWNER}/actions/runners/${token_type}-token"
      ;;
    repo)
      endpoint="${base_url}/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/${token_type}-token"
      ;;
    *)
      echo "Unsupported RUNNER_SCOPE '${RUNNER_SCOPE}'" >&2
      return 1
      ;;
  esac

  response=$(curl -sSf -X POST \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "${endpoint}") || {
      echo "Failed to request ${token_type} token from GitHub" >&2
      return 1
    }

  token=$(printf '%s' "${response}" | jq -r '.token // empty')
  if [[ -z "${token}" ]]; then
    echo "GitHub response did not contain a ${token_type} token" >&2
    return 1
  fi

  printf '%s' "${token}"
}

derive_scope_from_url() {
  local sanitized rest parts
  sanitized=${RUNNER_URL%.git}
  sanitized=${sanitized#https://}
  sanitized=${sanitized#http://}
  sanitized=${sanitized#github.com/}
  sanitized=${sanitized#github.com:}

  IFS='/' read -r -a parts <<< "${sanitized}"
  if (( ${#parts[@]} < 1 )); then
    echo "Unable to parse RUNNER_URL: ${RUNNER_URL}" >&2
    exit 1
  fi

  GITHUB_OWNER=${parts[0]}
  if (( ${#parts[@]} >= 2 )); then
    GITHUB_REPO=${parts[1]}
    RUNNER_SCOPE=${RUNNER_SCOPE:-repo}
  else
    RUNNER_SCOPE=${RUNNER_SCOPE:-org}
  fi
}

trap handle_signal SIGINT SIGTERM

if [[ -z "${RUNNER_URL:-}" ]]; then
  echo "RUNNER_URL is required (e.g. https://github.com/org/repo)" >&2
  exit 1
fi

derive_scope_from_url

RUNNER_NAME=${RUNNER_NAME:-$(hostname)}
RUNNER_WORKDIR=${RUNNER_WORKDIR:-_work}
RUNNER_LABELS=${RUNNER_LABELS:-self-hosted,linux}
RUNNER_SCOPE=${RUNNER_SCOPE:-repo}

if [[ -z "${RUNNER_TOKEN:-}" && -n "${GITHUB_PAT:-}" ]]; then
  echo "Requesting fresh registration token from GitHub..."
  RUNNER_TOKEN=$(request_github_token "registration")
fi

if [[ -z "${RUNNER_TOKEN:-}" ]]; then
  echo "RUNNER_TOKEN is required. Set it explicitly or provide GITHUB_PAT." >&2
  exit 1
fi

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
