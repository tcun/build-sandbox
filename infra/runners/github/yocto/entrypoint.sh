#!/bin/bash
set -euo pipefail

# Configuration from environment variables
RUNNER_REPO="${RUNNER_REPO:-}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-yocto,kas,rust,self-hosted}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/home/runner/work}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
RUNNER_RECONFIGURE="${RUNNER_RECONFIGURE:-false}"
RUNNER_REMOVE_ON_EXIT="${RUNNER_REMOVE_ON_EXIT:-false}"
RUNNER_STATE_DIR="${RUNNER_STATE_DIR:-/home/runner/work/.runner-state}"
YOCTO_FETCH_SSH_KEY="${YOCTO_FETCH_SSH_KEY:-}"
YOCTO_FETCH_SSH_HOST="${YOCTO_FETCH_SSH_HOST:-github.com}"

# Optional: allow GitHub Enterprise
GITHUB_URL="${GITHUB_URL:-https://github.com}"
if [[ "${RUNNER_TOKEN}" == "your_token_here" ]]; then
    RUNNER_TOKEN=""
fi

sanitize_yocto_env() {
    # Guard against inherited host/job vars that break bitbake fakeroot tasks.
    unset PSEUDO_DISABLED PSEUDO_PREFIX PSEUDO_LOCALSTATEDIR PSEUDO_PASSWD FAKEROOTKEY BB_PRESERVE_ENV BB_ENV_PASSTHROUGH || true
}

ensure_writable_dir() {
    local dir="$1"
    local uid gid
    uid="$(id -u)"
    gid="$(id -g)"

    mkdir -p "${dir}" 2>/dev/null || sudo mkdir -p "${dir}"

    if ! touch "${dir}/.runner-write-test" 2>/dev/null; then
        echo "WARN: ${dir} is not writable; attempting ownership repair." >&2
        sudo chown -R "${uid}:${gid}" "${dir}" || true
    fi

    if ! touch "${dir}/.runner-write-test" 2>/dev/null; then
        echo "ERROR: ${dir} is not writable by uid=${uid} gid=${gid}" >&2
        ls -ld "${dir}" >&2 || true
        exit 1
    fi

    rm -f "${dir}/.runner-write-test"
}

ensure_runner_workdir_writable() {
    local workdir="${RUNNER_WORKDIR}"
    ensure_writable_dir "${workdir}"
    mkdir -p "${workdir}/_PipelineMapping" "${workdir}/_temp" "${workdir}/_actions" "${workdir}/_tool"
}

ensure_yocto_cache_dirs_writable() {
    ensure_writable_dir "/cache/downloads"
    ensure_writable_dir "/cache/sstate-cache"
    ensure_writable_dir "/srv/yocto-artifacts"
}

configure_yocto_fetch_ssh() {
    local key_src="${YOCTO_FETCH_SSH_KEY}"
    local key_dst="${HOME}/.ssh/yocto_ci"
    local known_hosts_file="${HOME}/.ssh/known_hosts"

    if [[ ! -f "${key_src}" ]]; then
        echo "ERROR: YOCTO_FETCH_SSH_KEY file not found: ${key_src}" >&2
        return 1
    fi

    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"

    # In rootless podman, UID/GID mappings can make bind-mounted 0600 files
    # unreadable to the non-root container user. Retry with sudo if needed.
    if ! cp "${key_src}" "${key_dst}" 2>/dev/null; then
        echo "WARN: direct read of ${key_src} failed; retrying with sudo cp."
        sudo cp "${key_src}" "${key_dst}"
        sudo chown "$(id -u):$(id -g)" "${key_dst}"
    fi

    chmod 600 "${key_dst}"

    if ! command -v ssh-keyscan >/dev/null 2>&1; then
        echo "ERROR: ssh-keyscan not found. Install openssh-client in the runner image." >&2
        return 1
    fi

    ssh-keyscan -H "${YOCTO_FETCH_SSH_HOST}" > "${known_hosts_file}.tmp" 2>/dev/null || {
        echo "ERROR: Failed to populate known_hosts for ${YOCTO_FETCH_SSH_HOST}" >&2
        return 1
    }
    mv "${known_hosts_file}.tmp" "${known_hosts_file}"
    chmod 644 "${known_hosts_file}"

    GIT_SSH_COMMAND="ssh -i ${key_dst} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${known_hosts_file}"
    export GIT_SSH_COMMAND
    git config --global core.sshCommand "${GIT_SSH_COMMAND}"

    echo "Configured Git SSH command for Yocto fetches."
}

persist_runner_state() {
    mkdir -p "${RUNNER_STATE_DIR}"
    chmod 700 "${RUNNER_STATE_DIR}"

    for f in .runner .credentials .credentials_rsaparams; do
        if [[ -f "/home/runner/actions-runner/${f}" ]]; then
            cp "/home/runner/actions-runner/${f}" "${RUNNER_STATE_DIR}/${f}"
            chmod 600 "${RUNNER_STATE_DIR}/${f}" || true
        fi
    done
}

restore_runner_state() {
    if [[ ! -d "${RUNNER_STATE_DIR}" ]]; then
        return 0
    fi

    for f in .runner .credentials .credentials_rsaparams; do
        if [[ ! -f "/home/runner/actions-runner/${f}" && -f "${RUNNER_STATE_DIR}/${f}" ]]; then
            cp "${RUNNER_STATE_DIR}/${f}" "/home/runner/actions-runner/${f}"
            chmod 600 "/home/runner/actions-runner/${f}" || true
        fi
    done
}

# Validate required environment variables
if [[ -z "${RUNNER_REPO}" ]]; then
    echo "ERROR: RUNNER_REPO environment variable is required"
    echo "       Format: owner/repo (e.g., BackburnerLabs/savers-aps)"
    exit 1
fi

sanitize_yocto_env
ensure_runner_workdir_writable
ensure_yocto_cache_dirs_writable

if [[ -n "${YOCTO_FETCH_SSH_KEY}" ]]; then
    configure_yocto_fetch_ssh
else
    echo "WARN: YOCTO_FETCH_SSH_KEY is not set; canonical Yocto SSH fetches may fail." >&2
fi

if [[ -n "${RUNNER_TOKEN}" ]]; then
    echo "Runner registration mode: RUNNER_TOKEN (manual short-lived registration token)."
    echo "Token is only needed when (re)registering the runner." >&2
fi

cd /home/runner/actions-runner
restore_runner_state

need_registration=false
if [[ -f ".runner" ]]; then
    if [[ "${RUNNER_RECONFIGURE}" == "true" ]]; then
        echo "Reconfigure requested: removing existing local runner configuration..."
        rm -f .runner .credentials .credentials_rsaparams || true
        rm -f "${RUNNER_STATE_DIR}/.runner" "${RUNNER_STATE_DIR}/.credentials" "${RUNNER_STATE_DIR}/.credentials_rsaparams" || true
        need_registration=true
    else
        echo "Existing runner config found; reusing local credentials."
    fi
else
    need_registration=true
fi

if [[ "${need_registration}" == "true" ]]; then
    if [[ -z "${RUNNER_TOKEN}" ]]; then
        echo "ERROR: A runner registration token is required when no local runner config exists."
        echo "       Set RUNNER_TOKEN in the environment and restart this container."
        echo ""
        echo "       Manual token generation: ${GITHUB_URL}/${RUNNER_REPO}/settings/actions/runners/new"
        exit 1
    fi

    echo "Configuring GitHub Actions runner..."
    ./config.sh \
        --url "${GITHUB_URL}/${RUNNER_REPO}" \
        --token "${RUNNER_TOKEN}" \
        --name "${RUNNER_NAME}" \
        --labels "${RUNNER_LABELS}" \
        --work "${RUNNER_WORKDIR}" \
        --runnergroup "${RUNNER_GROUP}" \
        --unattended \
        --replace

    if [[ ! -f ".runner" ]]; then
        echo "ERROR: Runner registration did not persist local .runner config." >&2
        echo "       Verify RUNNER_REPO and token permissions, then retry." >&2
        exit 1
    fi

    persist_runner_state
fi

# Cleanup function for graceful shutdown
cleanup() {
    if [[ "${RUNNER_REMOVE_ON_EXIT}" == "true" ]]; then
        echo "Received shutdown signal, removing local runner configuration..."
        rm -f .runner .credentials .credentials_rsaparams || true
        rm -f "${RUNNER_STATE_DIR}/.runner" "${RUNNER_STATE_DIR}/.credentials" "${RUNNER_STATE_DIR}/.credentials_rsaparams" || true
    else
        persist_runner_state
        echo "Received shutdown signal, keeping runner registration (RUNNER_REMOVE_ON_EXIT=false)."
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Start the runner
echo "Starting GitHub Actions runner..."
exec ./run.sh
