# build-sandbox

This repository is a practical sandbox for rapidly iterating on build and release infrastructure.

The current focus is embedded workflows around:

- Rust application development
- Yocto-based image builds
- CI/CD automation for build, artifact publishing, release-candidate flow, and promotion

The intent is to move fast, validate ideas in real pipelines, and continuously improve tooling and conventions.  
Today the scope is Rust + Yocto, but this sandbox can expand into broader platform and infrastructure experiments over time.

## What This Repo Is For

- Prototype and harden CI/CD workflows before broader adoption
- Test reproducible artifact and release promotion patterns
- Exercise runner/container infrastructure with realistic embedded build workloads
- Keep a single place to iterate on scripts, recipes, and operational runbooks

## Local Requirements

- `cargo`
- `just`
- `kas`
- `podman` (or `podman-compose`)

## Common Commands

- `just build-dev` for local dev profile builds
- `just build-test` for local canonical test profile builds
- `just release-candidate <X.Y.Z>` to cut and push the next `vX.Y.Z-rc.N`

## CI Workflows

- `build-from-ref.yml`: manual `dev`/`test` build from branch/tag/SHA
- `release-candidate.yml`: automatic on `v*.*.*-rc.*` tag push
- `promote-candidate.yml`: manual promotion to stable without rebuild
- `yocto-test.yml`: canonical Yocto PR gate
- `infra-contract.yml`: lightweight PR contract checks for env/path consistency

## Environment Contract

Canonical variables:

- `YOCTO_ROOT`: required in CI, local default is `<repo>/build/yocto`
- `POKY_INIT`: optional override, default `${YOCTO_ROOT}/sources/poky/oe-init-build-env`
- `ARTIFACT_ROOT`: infra publish/serve root, default `/srv/yocto-artifacts`

Derived (never independently configured):

- `BUILD_DIR=${YOCTO_ROOT}/build/<machine>-<variant>`
- `DEPLOY_DIR=${BUILD_DIR}/tmp/deploy/images/<machine>`

Validation commands:

- `just ci::contract-check ci qemux86-64 test`
- `just infra::contract-check`

## Key Docs

- [First-Time Setup](docs/first-time-setup.md)
- [Release Candidate And Promotion Workflow](docs/release-workflow.md)
- [Versioning Proposal](docs/versioning.md)
