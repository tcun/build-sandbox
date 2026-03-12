#!/bin/bash
# Deploy GitHub Actions Runner to a build server
#
# Usage:
#   ./deploy-runner.sh deploy <server> [runner-name]
#   ./deploy-runner.sh units  <server>
#   ./deploy-runner.sh image  <server>
#
# Subcommands:
#   deploy  Build+transfer image, write env, copy quadlet unit files, restart services
#   units   Copy quadlet *.container files and restart services (fast)
#   image   Build+transfer image only (no config/unit changes)
#
# Example:
#   ./deploy-runner.sh deploy build-server.local yocto-runner-01
#   ./deploy-runner.sh units build-server.local
#
# Prerequisites:
#   - SSH access to the server
#   - Podman installed on the server
#   - GitHub credential for runner registration (will prompt if not set)

set -euo pipefail

# Configuration
REPO="BackburnerLabs/savers-aps"
IMAGE_NAME="yocto-runner"
IMAGE_TAG="latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

SUBCOMMAND="${1:-deploy}"
SERVER="${2:-}"
RUNNER_NAME="${3:-yocto-runner-$(hostname -s)}"

usage() {
        cat <<USAGE
Usage:
    $0 deploy <server> [runner-name]
    $0 units  <server>
    $0 image  <server>

Subcommands:
    deploy  Build+transfer image, write env, copy quadlet unit files, restart services
    units   Copy quadlet *.container files and restart services (fast)
    image   Build+transfer image only (no config/unit changes)

Arguments:
    server       SSH host (e.g., build-server.local or user@host)
    runner-name  Optional runner name (deploy only; default: yocto-runner-$(hostname -s))

Environment variables:
    RUNNER_PAT     Long-lived GitHub token used to mint runner registration tokens (deploy only; preferred)
    RUNNER_TOKEN   Short-lived GitHub runner registration token (deploy only; fallback; expires quickly)
    RUNNER_LABELS  Optional labels (deploy only)
    BB_NUMBER_THREADS / PARALLEL_MAKE  Optional build parallelism (deploy only)
USAGE
}

if [[ -z "${SERVER}" ]]; then
        usage
        exit 1
fi

case "${SUBCOMMAND}" in
        deploy|units|image)
                ;;
        -h|--help|help)
                usage
                exit 0
                ;;
        *)
                log_error "Unknown subcommand: ${SUBCOMMAND}"
                usage
                exit 1
                ;;
esac

if [[ "${SUBCOMMAND}" == "deploy" ]]; then
    # Prefer RUNNER_PAT (restart-safe). If not provided, allow RUNNER_TOKEN as a fallback.
    if [[ -z "${RUNNER_PAT:-}" && -z "${RUNNER_TOKEN:-}" ]]; then
        echo ""
        log_warn "No GitHub credential provided (RUNNER_PAT or RUNNER_TOKEN)"
        echo "Preferred (restart-safe): provide RUNNER_PAT (a long-lived GitHub token)."
        echo "Fallback (expires quickly): provide RUNNER_TOKEN from: https://github.com/${REPO}/settings/actions/runners/new"
        echo ""
        read -rsp "Enter RUNNER_PAT (recommended; leave blank to use RUNNER_TOKEN): " RUNNER_PAT
        echo ""

        if [[ -z "${RUNNER_PAT}" ]]; then
            read -rsp "Enter RUNNER_TOKEN (short-lived): " RUNNER_TOKEN
            echo ""
        fi
    fi

    if [[ -z "${RUNNER_PAT:-}" && -z "${RUNNER_TOKEN:-}" ]]; then
        log_error "RUNNER_PAT or RUNNER_TOKEN is required"
        exit 1
    fi

    if [[ -z "${RUNNER_PAT:-}" && -n "${RUNNER_TOKEN:-}" ]]; then
        log_warn "Using RUNNER_TOKEN (short-lived). Restarts will fail when it expires."
    fi
fi

log_info "Running '${SUBCOMMAND}' against ${SERVER}..."

# SSH options: avoid -tt (TTY) which corrupts binary data and echoes heredocs
SSH_OPTS=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YOCTO_DIR="$(dirname "${SCRIPT_DIR}")"

do_image() {
    # Build and transfer image
    log_info "Building container image..."
    podman build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "${YOCTO_DIR}/Containerfile" "${YOCTO_DIR}"

    log_info "Transferring image to ${SERVER} (compressed)..."
    podman save "${IMAGE_NAME}:${IMAGE_TAG}" | gzip -1 | ssh ${SSH_OPTS} "${SERVER}" "gunzip | podman load"
}

do_units() {
    log_info "Installing systemd quadlet unit files (.container)..."
    scp "${SCRIPT_DIR}/yocto-runner.container" "${SERVER}:~/.config/containers/systemd/"
    scp "${SCRIPT_DIR}/artifact-server.container" "${SERVER}:~/.config/containers/systemd/"

    log_info "Reloading and restarting services..."
    ssh ${SSH_OPTS} "${SERVER}" bash -s <<'EOF'
set -e
systemctl --user daemon-reload
systemctl --user restart yocto-runner || true
systemctl --user restart artifact-server || true
sleep 2
systemctl --user status yocto-runner --no-pager || true
echo ""
systemctl --user status artifact-server --no-pager || true
EOF
}

do_config() {
    log_info "Setting up configuration on server..."
    ssh ${SSH_OPTS} "${SERVER}" bash -s <<EOF
set -e

# Create config directory
mkdir -p ~/.config/yocto-runner
mkdir -p ~/.config/containers/systemd

# Create environment file with secrets
cat > ~/.config/yocto-runner/env <<'ENVFILE'
RUNNER_REPO=${REPO}
RUNNER_PAT=${RUNNER_PAT:-}
RUNNER_TOKEN=${RUNNER_TOKEN:-}
RUNNER_NAME=${RUNNER_NAME}
RUNNER_LABELS=${RUNNER_LABELS:-"yocto,kas,rust,self-hosted,linux,x64"}
BB_NUMBER_THREADS=${BB_NUMBER_THREADS:-"-j16"}
PARALLEL_MAKE=${PARALLEL_MAKE:-"-j16"}
ENVFILE

chmod 600 ~/.config/yocto-runner/env

echo "Configuration created at ~/.config/yocto-runner/env"
EOF
}

do_start() {
    log_info "Starting runner service..."
    ssh ${SSH_OPTS} "${SERVER}" bash -s <<'EOF'
set -e

# Reload systemd to pick up new quadlet units
systemctl --user daemon-reload

start_quadlet_unit() {
    local name="$1"

    # Quadlet often generates transient units under /run/user/<uid>/systemd/generator.
    # `systemctl enable` can fail for these. Starting them is sufficient, and
    # lingering ensures they come up on boot.
    if systemctl --user enable --now "${name}" 2>/tmp/quadlet-enable.err; then
        return 0
    fi

    if grep -qiE "transient|generated" /tmp/quadlet-enable.err; then
        echo "[WARN] ${name}: enable failed (generated unit). Starting without enable..."
        systemctl --user start "${name}"
        return 0
    fi

    echo "[ERROR] Failed to enable/start ${name}"
    cat /tmp/quadlet-enable.err
    return 1
}

# Start units (the generated service names are typically <ContainerName>.service)
start_quadlet_unit yocto-runner
start_quadlet_unit artifact-server

# Enable lingering so service runs without active login
loginctl enable-linger $(whoami)

# Show status
sleep 3
echo "=== Yocto Runner Status ==="
systemctl --user status yocto-runner --no-pager || true
echo ""
echo "=== Artifact Server Status ==="
systemctl --user status artifact-server --no-pager || true

echo ""
echo "=== Quadlet Generator Output (debug) ==="
ls -la "/run/user/$(id -u)/systemd/generator" 2>/dev/null | head -n 50 || true
EOF
}

case "${SUBCOMMAND}" in
    image)
        do_image
        ;;
    units)
        do_units
        ;;
    deploy)
        do_image
        do_config
        do_units
        do_start
        ;;
esac

log_info "Done."
echo ""
echo "Useful commands on ${SERVER}:"
echo "  systemctl --user status yocto-runner    # Check runner status"
echo "  systemctl --user status artifact-server # Check artifact server"
echo "  journalctl --user -xeu yocto-runner --no-pager      # Runner logs"
echo "  journalctl --user -xeu artifact-server --no-pager   # Artifact server logs"
echo "  systemctl --user daemon-reload          # Re-generate *.service from *.container"
echo ""
echo "Artifact server:"
echo "  http://localhost:8080/"
echo "  http://localhost:8080/dev/stm32mp25-disco/latest/images/"
echo ""
echo "Runner should appear at:"
echo "  https://github.com/${REPO}/settings/actions/runners"
