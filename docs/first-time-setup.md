# First-Time Setup Guide (Runner + Yocto Build Env + Artifacts)

This guide is the shortest reliable path to bootstrap a new project using this repo pattern.

## 1. Host Prerequisites

Install these on the runner host:

- `podman` (or `podman-compose`)
- `git`
- `just`
- enough disk for Yocto caches and workdir (100GB+ recommended)

Verify quickly:

```bash
podman --version
just --version
git --version
```

## 2. Configure Runner Environment

Create runner env file:

```bash
cp infra/runners/github/yocto/.env.example infra/runners/github/yocto/.env
```

Set at minimum in `infra/runners/github/yocto/.env`:

- `RUNNER_REPO=<owner/repo>`
- `RUNNER_TOKEN=<registration-token>` (required for first registration or when `RUNNER_RECONFIGURE=true`)
- `ARTIFACT_ROOT=/srv/yocto-artifacts` (or your desired shared path)

Optional but important:

- keep `RUNNER_RECONFIGURE=false` for persistent runners
- verify `RUNNER_LABELS` matches workflow `runs-on`

Validate and sync toolchain-derived defaults:

```bash
just infra::runner-env-sync
just infra::runner-env-validate
```

## 3. Configure Yocto Fetch SSH Key

For canonical `git+ssh` Yocto fetches, place key files here:

- `infra/runners/github/yocto/keys/yocto_ci`
- `infra/runners/github/yocto/keys/yocto_ci.pub`

Permissions:

```bash
chmod 600 infra/runners/github/yocto/keys/yocto_ci
chmod 644 infra/runners/github/yocto/keys/yocto_ci.pub
```

## 4. Configure Artifact Server

Create artifact-server env:

```bash
cp infra/services/artifact-server/.env.example infra/services/artifact-server/.env
```

Set `ARTIFACT_ROOT` to the same value used in runner `.env`.

## 5. Start Infrastructure Stacks

Bring up runner and artifact server:

```bash
just infra::runner-up
just infra::artifact-up
```

Check status/logs:

```bash
just infra::ps
just infra::runner-logs tail=200
just infra::artifact-logs tail=200
```

Expected runner log signal:

- `Configured Git SSH command for Yocto fetches.`

## 6. Validate Runner Registration In GitHub

In GitHub repo settings, confirm self-hosted runner is online and has labels matching workflows:

- `self-hosted, linux, x64, yocto` (plus any extras you kept)

## 7. Validate Build Environment End-To-End

Run the baseline validations in order:

```bash
just ci::guard-no-private-keys
just ci::contract-check local qemux86-64 test
just build-dev qemux86-64
just build-test qemux86-64 true
```

Then run a manual workflow dispatch (`build-from-ref.yml`) to confirm CI pathing and publish path creation.

## 8. Validate Artifact Publishing

After a successful publish step, verify artifacts are visible:

- `http://<artifact-host>:8080/artifacts/...`

And check `manifest.json` and `checksums.txt` exist in published output.

## 9. Release Path Smoke Test

1. Cut RC:

```bash
just release-candidate <MAJOR.MINOR.PATCH>
```

2. Wait for `.github/workflows/release-candidate.yml`.
3. Promote via `.github/workflows/promote-candidate.yml` (manual).

## 10. Project-Specific Values To Update For New Repos

Before first release in a new project, update these repo-bound values:

- `RUNNER_REPO` in `infra/runners/github/yocto/.env`
- Yocto source URL/branch defaults in `bsp/yocto/layers/meta-template-buildsandbox/recipes-apps/smoke-core/smoke-core.bb` (`SRC_URI`, `SOURCE_BRANCH`)
- Any README/docs links still pointing to previous repo owner/name

## 11. Common First-Day Failures

### Environment Contract (Canonical)

| Variable | Local default | CI requirement | Notes |
|---|---|---|---|
| `YOCTO_ROOT` | `<repo>/build/yocto` | required | single source for Yocto state paths |
| `POKY_INIT` | `${YOCTO_ROOT}/sources/poky/oe-init-build-env` | optional override | must be absolute path |
| `ARTIFACT_ROOT` | `/srv/yocto-artifacts` | required for infra runtime | runner and artifact-server must match |

Derived paths (do not set independently):

- `BUILD_DIR=${YOCTO_ROOT}/build/<machine>-<variant>`
- `DEPLOY_DIR=${BUILD_DIR}/tmp/deploy/images/<machine>`

Checks:

```bash
just ci::contract-check ci qemux86-64 test
just infra::contract-check
```

### Troubleshooting Matrix

| Symptom | Likely cause | Fix |
|---|---|---|
| `missing deploy dir` | wrong `YOCTO_ROOT` or variant path | run `just ci::contract-check ...` and fix `YOCTO_ROOT` |
| `missing ... oe-init-build-env` | `POKY_INIT` not resolvable from `YOCTO_ROOT` | set `POKY_INIT` or fix Yocto sources under `YOCTO_ROOT` |
| `is not an annotated tag` | RC tag created lightweight | use `just release-candidate <x.y.z>` |
| `Committer identity unknown` | git identity unset in runner | recipes now auto-set local identity; re-run workflow |
| `qemu-helper-native ... doesn't exist` | runqemu env lacks native helper | in active env run `bitbake qemu-helper-native` |
| artifacts not visible in server | runner/server `ARTIFACT_ROOT` mismatch | run `just infra::contract-check` and align both `.env` files |

## 12. Day-2 Ops Commands

```bash
just infra::runner-logs tail=200 follow=true
just infra::artifact-logs tail=200 follow=true
just infra::runner-down
just infra::artifact-down
```
