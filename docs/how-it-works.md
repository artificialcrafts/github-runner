# How It Works

This repository packages the GitHub Actions self‑hosted runner into a Docker container and provides a small wrapper script to run and manage it consistently. At a glance:

- A container registers with GitHub using values from an env file.
- The container mounts host directories under `/apps` so jobs can deploy to pre‑existing targets.
- Workflows target the runner via labels and operate on the mounted paths.

## Components

- Runner image (`docker/Dockerfile`)
  - Based on Ubuntu 22.04 with the GitHub Actions runner.
  - Intended to talk to the host Docker engine via the mounted socket for Docker‑based deploys.

- Entrypoint (`scripts/entrypoint.sh`)
  - Reads `RUNNER_URL`, derives scope (`repo`/`org`), and determines owner/repo from the URL.
  - Authenticates using either:
    - `RUNNER_TOKEN` (short‑lived, provided by you), or
    - `GITHUB_PAT` to request registration/removal tokens from GitHub’s API on startup/shutdown.
  - Registers the runner with labels, group, name, and optional `--ephemeral` mode.
  - Traps signals to deregister cleanly when the container stops.

- Compose file (`docker/docker-compose.yml`)
  - Service: `github-runner` with env vars and an `env_file` pointing at your chosen env.
  - Volumes:
    - `./work` → `/runner/_work` for the runner’s work dir.
    - `${HOST_APPS_PATH}` → `/apps` where your deployment targets live.
    - `/var/run/docker.sock` → inside the container so jobs can use Docker on the host.
    - `/home/artificialcrafts/.ssh` → `/runner/.ssh:ro` read‑only for Git over SSH.
  - `restart: unless-stopped` keeps the runner alive across host reboots.

- Helper script (`scripts/runner.sh`)
  - Selects and sources an env file (`RUNNER_ENV_FILE` or `-env <file>`), then runs Compose commands with a derived project name.
  - Derivation: uses `COMPOSE_PROJECT_NAME` if set, else `APP_NAME`/`RUNNER_NAME`, else the env filename.
  - Uses a single Compose invocation with `-p <project>` and `-f docker/docker-compose.yml`.
  - Applies `DOCKER_BUILDKIT=1` for build/start paths where image builds may occur.

## Mount Schemes and Paths

The container exposes `/apps`, which maps to a host path:

- Base‑dir mount: `HOST_APPS_PATH=/home/.../apps` → use `/apps/<app>/<env>` in workflows.
- Per‑app mount: `HOST_APPS_PATH=/home/.../apps/$APP_NAME` → use `/apps/<env>` in workflows.

Both are supported; pick one and keep workflows aligned with it. Example envs in `docker/envs/` show both variants.

## Job Flow

1) GitHub triggers a workflow targeting labels the runner advertises (e.g., `self-hosted, linux, deploy`).
2) The job runs on the container. The workflow either:
   - Repo‑in‑place: operates on a target under `/apps/...` that is a Git clone. A typical “sync” step does `git fetch/reset/clean` before running `deploy.sh`.
   - Artifact‑only: builds in the job workspace (Actions checkout), then deploys artifacts to `/apps/...` without running Git there.

The provided example (`scripts/examples/deploy-docker.yml`) demonstrates the repo‑in‑place pattern and includes a branch→path selection step.

## Tokens and Registration

- `RUNNER_TOKEN` – Provide a fresh token from GitHub UI/API before each (re)start.
- `GITHUB_PAT` – Provide once; the entrypoint requests registration and removal tokens automatically. Useful for ephemeral runners and unattended restarts.

Ephemeral mode (`RUNNER_EPHEMERAL=true`) registers a new runner per job and removes it when the job completes.

## Isolation, Naming, and Multiple Runners

- Compose project names isolate networks and container names across env files.
- This repo does not set a fixed `container_name`, so Compose uses names like `<project>-github-runner-1` to avoid conflicts.
- Run multiple runners by creating multiple env files and starting each via `scripts/runner.sh -env <file>`.

## Troubleshooting

- Container name conflict: Remove any legacy container with a fixed name using `docker rm -f <name>` and re‑start.
- Path mismatch: Ensure workflow paths under `/apps/...` match your chosen `HOST_APPS_PATH` scheme.
- Not a git repository: If using repo‑in‑place, seed a clone on the host or add a self‑heal clone step in the workflow before syncing.
- SSH failures: Ensure the mounted SSH directory has a valid key and `known_hosts` contains `github.com`.
- Work dir permissions: Grant UID 1000 write access to `docker/work` on the host.

## Day‑to‑Day Operations

- Start: `./scripts/runner.sh start [-env <file>]`
- Stop: `./scripts/runner.sh stop [-env <file>]`
- Restart: `./scripts/runner.sh restart [-env <file>]`
- Logs: `./scripts/runner.sh logs [service] [-env <file>]`
- Build image: `./scripts/runner.sh build [-env <file>]`

Refer to README for full setup, workflow examples, and troubleshooting tips.
