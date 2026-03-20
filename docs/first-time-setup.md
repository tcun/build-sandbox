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

- `missing deploy dir ... build/yocto/...`
  - Cause: path mismatch between `YOCTO_ROOT` and local default
  - Fix: ensure workflows export `YOCTO_ROOT` and use current scripts with path fallback logic

- `is not an annotated tag`
  - Cause: lightweight RC tag
  - Fix: create RC using `just release-candidate <x.y.z>`

- `Committer identity unknown` during promotion
  - Cause: runner git identity missing
  - Fix: current `just` recipes set local fallback identity automatically

- `runqemu ... qemu-helper-native ... doesn't exist`
  - Cause: booting downloaded artifacts without native helper in current build env
  - Fix: in current env run `bitbake qemu-helper-native` once

## 12. Day-2 Ops Commands

```bash
just infra::runner-logs tail=200 follow=true
just infra::artifact-logs tail=200 follow=true
just infra::runner-down
just infra::artifact-down
```

