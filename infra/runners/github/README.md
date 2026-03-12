# GitHub Self-Hosted Runners

Runner and artifact infrastructure is organized under `infra/`.

## Paths

### Yocto GitHub runner

`infra/runners/github/yocto/`

- `Containerfile`
- `compose.yaml`
- `.env.example`
- `entrypoint.sh`
- `quadlet/yocto-runner.container`

### Artifact server (Caddy)

`infra/services/artifact-server/`

- `compose.yaml`
- `.env.example`
- `Caddyfile`
- `quadlet/artifact-server.container`

## Notes

- Runner and artifact server are separate stacks now.
- `deploy-runner.sh` was intentionally removed.
- Use `podman-compose` (or your orchestrator of choice) from each directory.
