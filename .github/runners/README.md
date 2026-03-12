# GitHub Self-Hosted Runners

This directory documents how we run containerized, self-hosted GitHub Actions runners.

## Yocto runner

The Yocto runner image includes Ubuntu 22.04 + Yocto host deps + `kas` + Rust.

### Step 0: first-time setup (on the build server)

SSH to the server and install Podman + deps:

```bash
ssh savers-build
sudo apt update
sudo apt install -y podman uidmap slirp4netns fuse-overlayfs dbus-user-session
loginctl enable-linger savers
```

### Step 1: verify SSH + Podman

```bash
ssh savers-build 'whoami && hostname && podman --version'
```

### Step 2: generate a runner token

Generate a registration token here (expires quickly):

https://github.com/BackburnerLabs/savers-aps/settings/actions/runners/new

### Step 3: deploy using a `.env`

1) Create/update `.env` locally at `.github/runners/yocto/.env`.

2) Export values from `.env` and run the deploy script:

```bash
cd /home/bbl/workspace/savers-aps/.github/runners/yocto

# Export variables from .env into your shell
set -a
source .env
set +a

# Run deploy script (note: script lives under ./deploy)
cd /home/bbl/workspace/savers-aps/.github/runners/yocto
./deploy/deploy-runner.sh savers-build "${RUNNER_NAME:-yocto-runner-01}"
```

### Step 4: confirm it’s running

```bash
ssh savers-build 'systemctl --user status yocto-runner --no-pager'
ssh savers-build 'journalctl --user -u yocto-runner -n 200 --no-pager'
```

The runner should appear in GitHub:

https://github.com/BackburnerLabs/savers-aps/settings/actions/runners

## Repo layout (yocto runner)

In this repo snapshot, the Yocto runner files are located under `.github/runners/yocto/`:

```
.github/runners/yocto/
├── .env                 # local-only (DO NOT COMMIT)
├── Containerfile
├── compose.yaml
├── entrypoint.sh
└── deploy/
    ├── deploy-runner.sh
    └── yocto-runner.container
```
