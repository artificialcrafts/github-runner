# Deploy a New Runner

This guide walks you through creating and running an additional self‑hosted GitHub Actions runner using this repository.

## Prerequisites

- Docker and Docker Compose installed on the host.
- Host can reach `github.com` over HTTPS.
- Either a short‑lived GitHub runner registration token (per start) or a Personal Access Token (PAT) that lets the runner request tokens automatically.

## 1) Create an environment file

Create a new file under `docker/envs/` (e.g. `docker/envs/your-app.env`) based on `docker/envs/runner.env.example` and fill the values:

- `RUNNER_URL` – Repository or org URL (e.g. `https://github.com/your-org/your-app`).
- `RUNNER_NAME` – A human‑readable name for the runner.
- `RUNNER_LABELS` – Labels your workflows will target, e.g. `self-hosted,linux,deploy`.
- `RUNNER_IMAGE_NAME` – Local tag for the runner image, e.g. `your-app-github-runner:main`.
- `HOST_APPS_PATH` – Host path to mount at `/apps` inside the container. Choose one scheme and keep workflows consistent:
  - Base‑dir: `/home/you/apps` → workflows use `/apps/<app>/<env>`.
  - Per‑app: `/home/you/apps/$APP_NAME` → workflows use `/apps/<env>`.
- Authentication:
  - Either set `RUNNER_TOKEN` (short‑lived from GitHub UI/API), or
  - Set `GITHUB_PAT` so the runner can auto‑request registration/removal tokens.
- Optional: `RUNNER_EPHEMERAL=true` to auto‑remove the runner after each job.

Tip: Keep `RUNNER_LABELS` targeted and consistent across runners so jobs land where you expect.

## 2) Build (optional) and start the runner

Run these from the repository root. Prefer the flag form (no need to chmod):

```bash
# Flag form (recommended)
bash scripts/runner.sh build  -env your-app.env   # optional clean build
bash scripts/runner.sh start  -env your-app.env

# Alternative: environment variable form
RUNNER_ENV_FILE=envs/your-app.env bash scripts/runner.sh build  # optional
RUNNER_ENV_FILE=envs/your-app.env bash scripts/runner.sh start
```

Check logs:

```bash
bash scripts/runner.sh logs -env your-app.env
```

You should see the runner register and wait for jobs. The Compose project name is derived from your env (or `APP_NAME`/`RUNNER_NAME`) so multiple runners can run side‑by‑side without container name conflicts.

## 3) Add a workflow in your repository

Add a simple workflow that targets your runner’s labels to verify everything works. Example:

```yaml
name: Hello Runner
on: [workflow_dispatch]
jobs:
  demo:
    runs-on: [self-hosted, linux, deploy]
    steps:
      - run: echo "Runner $(uname -a) is alive"
```

For deployments, adapt `scripts/examples/deploy-docker.yml` to your mount scheme:

- Base‑dir mount: set paths like `/apps/<app>/<env>`.
- Per‑app mount: set paths like `/apps/<env>`.

If the deployment path is a Git clone, add a "sync" step to fetch/reset. If it’s artifact‑only, build in the job workspace and copy/rsync to `/apps/...` instead of running `git` there.

## 4) Operate the runner

- Stop: `./scripts/runner.sh stop -env your-app.env`
- Restart (e.g., after changing tokens/env): `./scripts/runner.sh restart -env your-app.env`
- Logs: `./scripts/runner.sh logs [service] -env your-app.env`

## Notes & Troubleshooting

- Container name conflict: This repo no longer sets a fixed `container_name`; Compose assigns names per project, avoiding collisions. If you have an old container with a fixed name, remove it with `docker rm -f <name>` once.
- "Not a git repository" in `/apps/...`: Either seed a clone on the host or add a self‑heal step to clone when missing.
- SSH: The compose file mounts `/home/artificialcrafts/.ssh` to `/runner/.ssh:ro`. Adjust that path if your SSH directory differs and ensure `known_hosts` includes `github.com`.
