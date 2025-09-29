# Clocktopus Self-Hosted GitHub Runner

This repository contains a Docker packaging of the GitHub Actions self-hosted runner that can live on the internal host alongside the Clocktopus containers. The runner phones out to GitHub, listens for workflow jobs, and can execute your existing `deploy.sh` scripts located in `apps/clocktopus-*`.

## What's inside

- `Dockerfile` – builds the runner image on top of Ubuntu 22.04.
- `scripts/entrypoint.sh` – registers the runner with GitHub and starts the service.
- `docker-compose.yml` – spins up the runner container, mounting the Clocktopus deployment directories and Docker socket.
- `.env.example` – template for the environment variables the runner needs.
- `examples/clocktopus-deploy.yml` – sample workflow to drop into the Clocktopus repo.

## Prerequisites

1. Docker and Docker Compose installed on the host machine.
2. Network access from the host to `github.com` over HTTPS (port 443).
3. Access to generate a **repository** or **organization** self-hosted runner registration token in GitHub (`Settings ▸ Actions ▸ Runners`). Tokens expire after one hour; fetch a fresh one each time you need to (re-)register.
4. The Clocktopus deployment directories available on the host (default assumption: `/home/artificialcrafts/apps/clocktopus-*`). Adjust the mount path via `HOST_APPS_PATH` in `.env` if your layout differs.

## Quick start

1. Clone this repository onto the internal host that can reach the Clocktopus Docker daemon and deployment scripts.
2. Copy the environment template and fill in the values:

   ```bash
   cp .env.example .env
   # Edit .env and add the fresh RUNNER_TOKEN from GitHub
   ```

   - `RUNNER_URL` should point to the GitHub repository that owns the workflows (e.g. `https://github.com/your-org/clocktopus`).
   - `RUNNER_TOKEN` is the one-time registration token from the GitHub UI/API.
   - `RUNNER_LABELS` defaults to `self-hosted,linux,deploy`. Workflows must request these labels.
   - `HOST_APPS_PATH` should match the directory on the host where your environments live (e.g. `/home/artificialcrafts/apps`).

3. Build and start the runner container:

   ```bash
   docker compose up --build -d
   ```

   The container keeps a persistent work directory in `./work` and mounts:

   - `/apps` → `${HOST_APPS_PATH}` on the host (so workflows can run `deploy.sh`).
   - `/var/run/docker.sock` → the host Docker socket (optional, but useful if `deploy.sh` manipulates Docker).

4. Watch the logs the first time to confirm successful registration and job execution:

   ```bash
   docker compose logs -f
   ```

5. When the registration token expires or you redeploy the container, fetch a fresh token, update `.env`, and restart:

   ```bash
   docker compose down
   # update RUNNER_TOKEN in .env
   docker compose up -d
   ```

   If you prefer ephemeral runners (new registration per job), uncomment `RUNNER_EPHEMERAL=true` in `.env`.

## Example workflow for the Clocktopus repo

Add a workflow similar to [`examples/clocktopus-deploy.yml`](examples/clocktopus-deploy.yml) to the Clocktopus repository (e.g. `.github/workflows/deploy.yml`):

```yaml
name: Deploy Clocktopus

on:
  push:
    branches:
      - development
      - next
      - main

jobs:
  deploy:
    runs-on: [self-hosted, linux, deploy]
    steps:
      - name: Select deployment target
        run: |
          case "${GITHUB_REF_NAME}" in
            development)
              echo "TARGET_DIR=/apps/clocktopus-development" >> "$GITHUB_ENV"
              ;;
            next)
              echo "TARGET_DIR=/apps/clocktopus-next" >> "$GITHUB_ENV"
              ;;
            main)
              echo "TARGET_DIR=/apps/clocktopus" >> "$GITHUB_ENV"
              ;;
            *)
              echo "Unsupported branch ${GITHUB_REF_NAME}" >&2
              exit 1
              ;;
          esac
      - name: Checkout repository (optional)
        uses: actions/checkout@v4
      - name: Run deploy script
        run: |
          if [[ ! -x "${TARGET_DIR}/deploy.sh" ]]; then
            echo "deploy.sh missing or not executable in ${TARGET_DIR}" >&2
            exit 1
          fi
          cd "${TARGET_DIR}"
          ./deploy.sh
```

### Notes

- The workflow relies on the `/apps` mount exposed by the runner container. Adjust the mount or paths if your deployment scripts live elsewhere.
- If your `deploy.sh` script rebuilds Docker images, ensure the runner UID has permission to access the socket. By default the container runs as the `runner` user; you may need to add it to the host Docker group ID (set `group_add` in `docker-compose.yml`).
- Restrict which workflows can target the runner by scoping `RUNNER_URL` to a single repository and assigning unique labels (`runs-on`).
- Consider using GitHub environments with required reviewers/secrets for additional safety gates before deployments.

## Managing updates

- To update the runner version, change `RUNNER_VERSION` in `Dockerfile` and rebuild.
- Keep the host patched and monitor `docker compose logs` for any registration failures.
- Use multiple runner instances (with different `RUNNER_NAME` and `RUNNER_LABELS`) if you need parallel deployments per environment.
