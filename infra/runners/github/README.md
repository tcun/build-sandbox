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
- Runner registration uses `RUNNER_TOKEN` only (no PAT flow in this repo setup).
- Runner credentials are persisted under `/home/runner/work/.runner-state` (on the `yocto-workdir` volume), so container recreation does not require a new token unless you explicitly reconfigure/remove.

## Yocto Canonical Fetch SSH Key

For canonical Yocto `git+ssh` fetches, place a deploy key at:

- private key: `infra/runners/github/yocto/keys/yocto_ci`
- public key: `infra/runners/github/yocto/keys/yocto_ci.pub`

Permissions:

- `chmod 600 infra/runners/github/yocto/keys/yocto_ci`
- `chmod 644 infra/runners/github/yocto/keys/yocto_ci.pub`

The compose stack mounts `./keys` read-only at `/run/yocto-ssh` in the runner container and uses:

- `YOCTO_FETCH_SSH_KEY=/run/yocto-ssh/yocto_ci`

### Validation

1. Start runner stack:
   - `just infra::runner-up`
2. Verify startup log includes SSH setup:
   - `just infra::runner-logs tail=200 follow=false`
   - Expect line: `Configured Git SSH command for Yocto fetches.`
3. Verify the key is present in container:
   - `podman exec yocto-runner bash -lc 'ls -l ~/.ssh/yocto_ci ~/.ssh/known_hosts'`
