# Clocktopus Self-Hosted GitHub Runner

This repository contains a Docker packaging of the GitHub Actions self-hosted runner that can live on the internal host alongside the Clocktopus containers. The runner phones out to GitHub, listens for workflow jobs, and can execute your existing `deploy.sh` scripts located in `apps/clocktopus-*`.

## What's inside

- `docker/Dockerfile` – builds the runner image on top of Ubuntu 22.04.
- `docker/docker-compose.yml` – spins up the runner container, mounting the Clocktopus deployment directories and Docker socket.
- `docker/envs/runner.env.example` – template for the environment variables the runner needs.
- `scripts/entrypoint.sh` – registers the runner with GitHub and starts the service.
- `examples/clocktopus-deploy.yml` – sample workflow to drop into the Clocktopus repo.

## Prerequisites

1. Docker and Docker Compose installed on the host machine.
2. Network access from the host to `github.com` over HTTPS (port 443).
3. Access to generate a **repository** or **organization** self-hosted runner registration token in GitHub (`Settings ▸ Actions ▸ Runners`). Tokens expire after one hour; fetch a fresh one each time you need to (re-)register.
4. The Clocktopus deployment directories available on the host (default assumption: `/home/artificialcrafts/apps/clocktopus-*`). Adjust the mount path via `HOST_APPS_PATH` in your chosen env file if your layout differs.

## Quick start

1. Clone this repository onto the internal host that can reach the Clocktopus Docker daemon and deployment scripts.
2. Create an environment file under `docker/envs/` based on the template and fill in the values:

   ```bash
   cp docker/envs/runner.env.example docker/envs/clocktopus.env
   # Edit docker/envs/clocktopus.env and add your credentials
   ```

   - `RUNNER_URL` should point to the GitHub repository that owns the workflows (e.g. `https://github.com/your-org/clocktopus`).
   - Provide either a short-lived `RUNNER_TOKEN` from the GitHub UI/API **or** set `GITHUB_PAT` to a Personal Access Token with `repo` + `admin:repo_hook` (for repos) or `admin:org` (for org runners). When `GITHUB_PAT` is present the container auto-requests fresh registration/removal tokens on every start/stop.
   - `RUNNER_LABELS` defaults to `self-hosted,linux,deploy`. Workflows must request these labels.
   - `HOST_APPS_PATH` should match the directory on the host where your environments live (e.g. `/home/artificialcrafts/apps`).

3. Build and start the runner container (from the repository root), pointing Compose at the desired env file via `RUNNER_ENV_FILE` (defaults to `envs/clocktopus.env`):

   ```bash
   export RUNNER_ENV_FILE=envs/clocktopus.env
   docker compose -f docker/docker-compose.yml up --build -d
   ```

   (If you open a new shell later, re-export `RUNNER_ENV_FILE` or prefix compose commands with `RUNNER_ENV_FILE=...`.)

   The container keeps a persistent work directory in `./work` and mounts:

   - `/apps` → `${HOST_APPS_PATH}` on the host (so workflows can run `deploy.sh`).
   - `/var/run/docker.sock` → the host Docker socket (optional, but useful if `deploy.sh` manipulates Docker).

4. Watch the logs the first time to confirm successful registration and job execution:

   ```bash
   docker compose -f docker/docker-compose.yml logs -f github-runner
   ```

5. If you did not supply `GITHUB_PAT`, fetch a fresh registration token each time you restart the container, update your chosen env file, and bring it back up:

   ```bash
   docker compose -f docker/docker-compose.yml down
   # update RUNNER_TOKEN in docker/envs/clocktopus.env
   docker compose -f docker/docker-compose.yml up -d
   ```

   If `GITHUB_PAT` is set you can simply restart the compose stack—it will request new registration/removal tokens automatically. For ephemeral runners (new registration per job), uncomment `RUNNER_EPHEMERAL=true` in the env file.

### Fetching tokens via CLI

- GitHub CLI: `gh auth login` (once) then `gh repo runnertoken your-org/clocktopus` to print a fresh registration token, or `gh api --method POST repos/your-org/clocktopus/actions/runners/registration-token --jq .token`.
- cURL: `curl -s -X POST -H "Authorization: Bearer $GITHUB_PAT" -H "Accept: application/vnd.github+json" https://api.github.com/repos/your-org/clocktopus/actions/runners/registration-token | jq -r .token`.
- Replace `repos/...` with `orgs/<org>` if you register an organization-level runner.

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
- If your `deploy.sh` script rebuilds Docker images, ensure the runner UID has permission to access the socket. By default the container runs as the `runner` user; you may need to add it to the host Docker group ID (set `group_add` in `docker/docker-compose.yml`).
- Restrict which workflows can target the runner by scoping `RUNNER_URL` to a single repository and assigning unique labels (`runs-on`).
- Consider using GitHub environments with required reviewers/secrets for additional safety gates before deployments.

## Managing updates

- To update the runner version, change `RUNNER_VERSION` in `docker/Dockerfile` and rebuild.
- Keep the host patched and monitor `docker compose -f docker/docker-compose.yml logs` for any registration failures.
- Use multiple runner instances (with different `RUNNER_NAME` and `RUNNER_LABELS`) if you need parallel deployments per environment.
