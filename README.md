# build-sandbox repo

My personal sandbox repo for mainly experimenting with monorepo and automation infrastructure.

## Manual Installs

cargo
just-lsp
kas
podman

## CI/CD Commands

- `just build-dev` for local dev profile build
- `just build-test` for local canonical test profile build
- `just release-candidate <X.Y.Z>` to cut and push the next `vX.Y.Z-rc.N` tag

GitHub workflows:

- `build-from-ref.yml` (manual `dev`/`test` build from branch/tag/SHA)
- `release-candidate.yml` (automatic on `v*.*.*-rc.*` tag push)
- `promote-candidate.yml` (manual promotion to stable without rebuild)
