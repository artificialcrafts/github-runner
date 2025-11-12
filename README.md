# Clocktopus Self-Hosted GitHub Runner

This repository contains a Dockerized GitHub Actions self-hosted runner you can run on an internal host. The runner phones out to GitHub, listens for jobs, and runs your existing `deploy.sh` scripts against directories mounted from the host (under `/apps` inside the container).

## What's Inside

- `docker/Dockerfile` – Runner image based on Ubuntu 22.04.
- `docker/docker-compose.yml` – Defines the runner service and host mounts.
- `docker/envs/runner.env.example` – Template for required env vars.
- `docker/envs/clocktopus.env`, `docker/envs/playground.env` – Example envs for two repos.
- `scripts/entrypoint.sh` – Registers the runner and starts it.
- `scripts/runner.sh` – Helper to start/stop/build with the right env.
- `scripts/examples/deploy-docker.yml` – Example GitHub Actions workflow.

## Prerequisites

- Docker and Docker Compose available on the host (`docker-compose` CLI or the v2 plugin).
- Host can reach `github.com` over HTTPS (port 443).
- Ability to create a repository or organization runner token in GitHub (`Settings ▸ Actions ▸ Runners`). Tokens expire after 1 hour unless you use a PAT to request them automatically.

## Setup

1) Create an env file under `docker/envs/` based on the example and fill values:

- `RUNNER_URL` – Repository or org URL (e.g. `https://github.com/your-org/clocktopus`).
- `RUNNER_TOKEN` or `GITHUB_PAT` – Set one:
  - Short‑lived `RUNNER_TOKEN` from GitHub UI/API, or
  - Long‑lived `GITHUB_PAT` with required scopes so the runner can request tokens on startup/shutdown.
- `RUNNER_NAME`, `RUNNER_LABELS`, `RUNNER_GROUP` – Stick to labels you’ll target in workflows.
- `RUNNER_IMAGE_NAME` – Local image tag to build/use.
- `HOST_APPS_PATH` – Host path mounted to `/apps` inside the container. Choose one scheme and make your workflows match it:
  - Base‑dir mount: `/home/artificialcrafts/apps` → use `/apps/<app>/<env>` in workflows.
  - Per‑app mount: `/home/artificialcrafts/apps/$APP_NAME` → use `/apps/<env>` in workflows.
- `RUNNER_UID`/`RUNNER_GID` – UID/GID to run as inside the container (defaults are fine on most hosts).
- Optional: `RUNNER_EPHEMERAL=true` for ephemeral registration per job.

Note: The compose file binds the host SSH directory at `/home/artificialcrafts/.ssh` into the container at `/runner/.ssh:ro`. Adjust the path in `docker/docker-compose.yml` if your SSH directory is different. Ensure `known_hosts` contains `github.com` and the key is accepted by GitHub.

2) Build and start the runner using the helper script (from repo root):

- One‑time build (optional): `RUNNER_ENV_FILE=envs/your.env ./scripts/runner.sh build`
- Start: `RUNNER_ENV_FILE=envs/your.env ./scripts/runner.sh start`

Short form: `./scripts/runner.sh start -env your.env` (the script resolves `envs/your.env`). If you omit it entirely, the default is `envs/clocktopus.env`.

3) Check logs to confirm registration and readiness:

- `./scripts/runner.sh logs` or `./scripts/runner.sh logs github-runner`

If you see permission issues in the work dir, grant UID 1000 write access to `docker/work` on the host:

- `sudo chown -R 1000:1000 docker/work && sudo chmod -R u+rwX docker/work`

## Using In Workflows

The container exposes `/apps` which maps to `${HOST_APPS_PATH}` on the host. Ensure your workflow paths match your chosen mount scheme.

Repo‑in‑place pattern (recommended if `/apps/...` already contains clones):

- Pick a target path per branch and run deployment from there. Example uses `git fetch/reset/clean` so the repo in `/apps/...` stays up‑to‑date.
- See `scripts/examples/deploy-docker.yml` for a working example. Adapt the `DEV_PATH/NEXT_PATH/MAIN_PATH` values to your chosen mount scheme.

If a target path is not a git repo, add a self‑heal step before sync to clone once:

```bash
mkdir -p "$TARGET_DIR"
if [ ! -d "$TARGET_DIR/.git" ]; then
  git clone --branch "$TARGET_BRANCH" "git@github.com:${GITHUB_REPOSITORY}.git" "$TARGET_DIR"
fi
git -C "$TARGET_DIR" fetch --prune
git -C "$TARGET_DIR" reset --hard "origin/$TARGET_BRANCH"
git -C "$TARGET_DIR" clean -fd
```

Artifact‑only pattern (build in workspace, deploy to `/apps`):

- Checkout stays in the runner workspace; `deploy.sh` copies/rsyncs artifacts to `${PATH}` under `/apps`.
- In this pattern you should not run `git` inside `/apps/...`.

## Operating The Runner

- Start: `./scripts/runner.sh start [-env <file>]`
- Stop: `./scripts/runner.sh stop [-env <file>]`
- Restart: `./scripts/runner.sh restart [-env <file>]`
- Logs: `./scripts/runner.sh logs [service] [-env <file>]` (default service `github-runner`)
- Build image: `./scripts/runner.sh build [-env <file>]`

Notes:

- Multiple env files = multiple isolated runner projects. The script derives the Compose project name from `COMPOSE_PROJECT_NAME` (if set) or from `APP_NAME`/`RUNNER_NAME`/env filename. Container names are not fixed (we don’t set `container_name`) to avoid collisions across projects.
- Only `RUNNER_ENV_FILE` is exported for Compose so the `env_file:` reference works. All other values are sourced from your chosen env file.

## Troubleshooting

- Container name conflict on start: remove any old container with a fixed name (from older versions) using `docker rm -f <name>`; current compose uses namespaced defaults like `<project>-github-runner-1`.
- Paths don’t exist inside the container: ensure your `HOST_APPS_PATH` matches your workflow paths (base‑dir vs per‑app scheme).
- “Not a git repository” in `/apps/...`: either seed clones on the host or add the self‑heal snippet above so the workflow clones when missing.
- SSH issues: make sure `/home/artificialcrafts/.ssh` on the host has a key GitHub accepts and `known_hosts` contains `github.com`.

## Managing Updates

- Update the runner version by editing `RUNNER_VERSION` in `docker/Dockerfile`, then rebuild.
- Monitor with `./scripts/runner.sh logs` and keep the host OS updated.
- Spin up additional runners with different env files if you need parallelism or isolation.
