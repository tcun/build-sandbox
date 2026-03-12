#!/bin/bash
set -euo pipefail

# Configuration from environment variables
RUNNER_REPO="${RUNNER_REPO:-}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
RUNNER_PAT="${RUNNER_PAT:-${GITHUB_TOKEN:-}}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-yocto,kas,rust,self-hosted}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/home/runner/work}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"

# Optional: allow GitHub Enterprise
GITHUB_URL="${GITHUB_URL:-https://github.com}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

fetch_registration_token() {
    local scope
    local endpoint

    if [[ -z "${RUNNER_PAT}" ]]; then
        return 1
    fi

    # If RUNNER_REPO includes a slash, treat it as owner/repo; otherwise treat it as an org name.
    if [[ "${RUNNER_REPO}" == */* ]]; then
        scope="repo"
        endpoint="${GITHUB_API_URL}/repos/${RUNNER_REPO}/actions/runners/registration-token"
    else
        scope="org"
        endpoint="${GITHUB_API_URL}/orgs/${RUNNER_REPO}/actions/runners/registration-token"
    fi

    echo "Requesting new runner registration token (${scope})..."

    # Curl will exit non-zero on HTTP errors; capture the body for diagnostics.
    local response
    response="$(curl -fsSL \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Authorization: Bearer ${RUNNER_PAT}" \
        "${endpoint}")" || {
        echo "ERROR: Failed to request registration token from GitHub." >&2
        echo "       Endpoint: ${endpoint}" >&2
        echo "       Check RUNNER_PAT permissions and RUNNER_REPO value." >&2
        return 2
    }

    # Response format: {"token":"...","expires_at":"..."}
    local token
    token="$(echo "${response}" | jq -r '.token // empty')"
    if [[ -z "${token}" ]]; then
        echo "ERROR: GitHub API response did not include a token." >&2
        echo "       Endpoint: ${endpoint}" >&2
        echo "       Response: ${response}" >&2
        return 3
    fi

    RUNNER_TOKEN="${token}"
    export RUNNER_TOKEN
}

# Validate required environment variables
if [[ -z "${RUNNER_REPO}" ]]; then
    echo "ERROR: RUNNER_REPO environment variable is required"
    echo "       Format: owner/repo (e.g., BackburnerLabs/savers-aps)"
    exit 1
fi

# If a registration token isn't provided, try minting one from a long-lived token.
if [[ -z "${RUNNER_TOKEN}" ]]; then
    if [[ -n "${RUNNER_PAT}" ]]; then
        fetch_registration_token
    fi
fi

if [[ -z "${RUNNER_TOKEN}" ]]; then
    echo "ERROR: A runner registration token is required."
    echo "       Provide either:" 
    echo "         - RUNNER_TOKEN (short-lived; expires quickly)" 
    echo "         - RUNNER_PAT (long-lived token used to mint RUNNER_TOKEN automatically)" 
    echo "" 
    echo "       Manual token generation: ${GITHUB_URL}/${RUNNER_REPO}/settings/actions/runners/new" 
    exit 1
fi

cd /home/runner/actions-runner

# Remove any existing runner configuration
if [[ -f ".runner" ]]; then
    echo "Removing existing runner configuration..."
    ./config.sh remove --token "${RUNNER_TOKEN}" || true
fi

# Configure the runner
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

# Cleanup function for graceful shutdown
cleanup() {
    echo "Received shutdown signal, removing runner..."
    ./config.sh remove --token "${RUNNER_TOKEN}" || true
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Start the runner
echo "Starting GitHub Actions runner..."
exec ./run.sh
