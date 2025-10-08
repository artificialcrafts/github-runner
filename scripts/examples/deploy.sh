#!/bin/bash
set -euo pipefail

# --- config ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$SCRIPT_DIR/deploy.env}"
if [[ ! -f "$DEPLOY_ENV_FILE" ]]; then
  echo "Error: Configuration file not found at $DEPLOY_ENV_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$DEPLOY_ENV_FILE"

: "${APP_NAME:?APP_NAME must be set in deploy.env}"
: "${DEFAULT_BRANCH_IMAGE_TAG:?DEFAULT_BRANCH_IMAGE_TAG must be set in deploy.env}"
: "${DEFAULT_BRANCH_HOST_PORT:?DEFAULT_BRANCH_HOST_PORT must be set in deploy.env}"

sanitize_branch_key() {
  local key="$1"
  key="${key//[^A-Za-z0-9]/_}"
  echo "$key"
}

lookup_branch_value() {
  local prefix="$1" branch="$2" fallback="$3"
  local sanitized
  sanitized="$(sanitize_branch_key "$branch")"
  local var_name="${prefix}_${sanitized}"
  if [[ -n ${!var_name:-} ]]; then
    echo "${!var_name}"
  else
    echo "$fallback"
  fi
}

# --- repo ---
echo "Updating repo..."
git pull

# --- Vars ---
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
GIT_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [[ -z "$GIT_TAG" ]]; then
  echo "Error: No git tag reachable from HEAD. Aborting build for branch $BRANCH." >&2
  exit 1
fi
TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")
export DOCKER_BUILDKIT=1

IMAGE_TAG="$(lookup_branch_value "BRANCH_IMAGE_TAG" "$BRANCH" "$DEFAULT_BRANCH_IMAGE_TAG")"
HOST_PORT="$(lookup_branch_value "BRANCH_HOST_PORT" "$BRANCH" "$DEFAULT_BRANCH_HOST_PORT")"

IMAGE_NAME="$APP_NAME:$IMAGE_TAG"
CONTAINER_NAME="${APP_NAME}-${IMAGE_TAG}"
CACHE_ROOT="${CACHE_ROOT:-.docker-cache}"
CACHE_DIR="$CACHE_ROOT/$IMAGE_TAG"
BUILD_CACHE_LIMIT="${BUILD_CACHE_LIMIT:-6GB}"
MAX_IMAGE_AGE="${MAX_IMAGE_AGE:-168h}" # default: prune dangling images older than 7 days

mkdir -p "$CACHE_DIR"
echo "Using build cache directory $CACHE_DIR (limit $BUILD_CACHE_LIMIT)."

# --- Deploy ---
echo "Building new image $IMAGE_NAME for branch $BRANCH (tag: $GIT_TAG)..."

echo "Building image $IMAGE_NAME..."
COMMON_BUILD_ARGS=(
  --build-arg BUILD_TIMESTAMP="$TIMESTAMP"
  --build-arg GIT_BRANCH="$BRANCH"
  --build-arg GIT_TAG="$GIT_TAG"
  --label app="$APP_NAME"
  --label branch="$BRANCH"
  -t "$IMAGE_NAME"
)

if [ -n "${DOCKERFILE_PATH:-}" ] && [ -f "$DOCKERFILE_PATH" ]; then
  COMMON_BUILD_ARGS=(-f "$DOCKERFILE_PATH" "${COMMON_BUILD_ARGS[@]}")
fi

if docker buildx version >/dev/null 2>&1; then
  USE_PERSISTENT_CACHE=0
  BUILDX_DRIVER=""

  # Prefer persistent cache unless the selected driver lacks support.
  if BUILDX_INSPECT_OUTPUT=$(docker buildx inspect 2>/dev/null); then
    BUILDX_DRIVER=$(awk '/^Driver:/ {print $2; exit}' <<<"$BUILDX_INSPECT_OUTPUT")
    if [[ "$BUILDX_DRIVER" == "docker" ]]; then
      echo "buildx driver '$BUILDX_DRIVER' does not support cache export; skipping persistent cache."
    else
      USE_PERSISTENT_CACHE=1
    fi
  else
    echo "docker buildx inspect failed; continuing without persistent cache." >&2
  fi

  BUILD_CMD=(docker buildx build)
  if (( USE_PERSISTENT_CACHE )); then
    BUILD_CMD+=(
      --cache-from "type=local,src=$CACHE_DIR"
      --cache-to "type=local,dest=$CACHE_DIR,mode=max"
    )
  fi
  BUILD_CMD+=(
    --load
    "${COMMON_BUILD_ARGS[@]}"
    .
  )
else
  echo "docker buildx not available; falling back to docker build without persistent cache." >&2
  BUILD_CMD=(
    docker build
    "${COMMON_BUILD_ARGS[@]}"
    .
  )
fi

"${BUILD_CMD[@]}"

echo "Stopping/removing existing container $CONTAINER_NAME (if any)..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm "$CONTAINER_NAME" 2>/dev/null || true

echo "Running container $CONTAINER_NAME on :$HOST_PORT -> :80 ..."
# Pass env file if present so server can proxy statistics
RUN_ARGS=(
  docker run -d
  --name "$CONTAINER_NAME"
  -p "$HOST_PORT:80"
  --restart unless-stopped
  --label app="$APP_NAME"
  --label branch="$BRANCH"
  -e GIT_BRANCH="$BRANCH"
  -e GIT_TAG="$GIT_TAG"
)

if [ -f .env ]; then
  echo "Using environment from .env"
  RUN_ARGS+=(--env-file .env)
fi

RUN_ARGS+=("$IMAGE_NAME")

"${RUN_ARGS[@]}"

# Cleanup
echo "Tidying up old images and caches..."
# Remove dangling app images older than configured window to keep disk usage in check
docker image prune --force \
  --filter "label=app=$APP_NAME" \
  --filter "until=$MAX_IMAGE_AGE" >/dev/null || true

# Keep build cache size under control while still leveraging layer reuse
docker builder prune --force --keep-storage "$BUILD_CACHE_LIMIT" >/dev/null || true

# Show status
echo "Deployment done. Current running containers:"
docker ps
