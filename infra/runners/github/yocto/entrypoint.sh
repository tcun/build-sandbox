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
RUNNER_RECONFIGURE="${RUNNER_RECONFIGURE:-false}"
RUNNER_REMOVE_ON_EXIT="${RUNNER_REMOVE_ON_EXIT:-false}"

# Optional: allow GitHub Enterprise
GITHUB_URL="${GITHUB_URL:-https://github.com}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

# Common placeholder values that should be treated as unset.
if [[ "${RUNNER_PAT}" == "your_token_here" ]]; then
    RUNNER_PAT=""
fi
if [[ "${RUNNER_TOKEN}" == "your_token_here" ]]; then
    RUNNER_TOKEN=""
fi

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

fetch_remove_token() {
    local endpoint

    if [[ -z "${RUNNER_PAT}" ]]; then
        return 1
    fi

    if [[ "${RUNNER_REPO}" == */* ]]; then
        endpoint="${GITHUB_API_URL}/repos/${RUNNER_REPO}/actions/runners/remove-token"
    else
        endpoint="${GITHUB_API_URL}/orgs/${RUNNER_REPO}/actions/runners/remove-token"
    fi

    local response
    response="$(curl -fsSL \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Authorization: Bearer ${RUNNER_PAT}" \
        "${endpoint}")" || return 2

    local token
    token="$(echo "${response}" | jq -r '.token // empty')"
    [[ -n "${token}" ]] || return 3
    echo "${token}"
}

# Validate required environment variables
if [[ -z "${RUNNER_REPO}" ]]; then
    echo "ERROR: RUNNER_REPO environment variable is required"
    echo "       Format: owner/repo (e.g., BackburnerLabs/savers-aps)"
    exit 1
fi

cd /home/runner/actions-runner

need_registration=false
if [[ -f ".runner" ]]; then
    if [[ "${RUNNER_RECONFIGURE}" == "true" ]]; then
        echo "Reconfigure requested: removing existing runner configuration..."
        REMOVE_TOKEN="$(fetch_remove_token || true)"
        if [[ -n "${REMOVE_TOKEN}" ]]; then
            ./config.sh remove --token "${REMOVE_TOKEN}" || true
        else
            echo "WARN: unable to fetch remove token; proceeding with local cleanup only" >&2
            rm -f .runner .credentials .credentials_rsaparams || true
        fi
        need_registration=true
    else
        echo "Existing runner config found; reusing local credentials."
    fi
else
    need_registration=true
fi

if [[ "${need_registration}" == "true" ]]; then
    # Prefer minting a fresh short-lived registration token from RUNNER_PAT
    # when available. This avoids expired RUNNER_TOKEN reuse.
    if [[ -n "${RUNNER_PAT}" ]]; then
        fetch_registration_token
    fi

    if [[ -z "${RUNNER_TOKEN}" ]]; then
        echo "ERROR: A runner registration token is required for first-time registration."
        echo "       Provide either:"
        echo "         - RUNNER_TOKEN (short-lived; expires quickly)"
        echo "         - RUNNER_PAT (long-lived token used to mint RUNNER_TOKEN automatically)"
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
fi

# Cleanup function for graceful shutdown
cleanup() {
    if [[ "${RUNNER_REMOVE_ON_EXIT}" == "true" ]]; then
        echo "Received shutdown signal, removing runner registration..."
        REMOVE_TOKEN="$(fetch_remove_token || true)"
        if [[ -n "${REMOVE_TOKEN}" ]]; then
            ./config.sh remove --token "${REMOVE_TOKEN}" || true
        else
            echo "WARN: unable to fetch remove token during shutdown; leaving registration in GitHub." >&2
        fi
    else
        echo "Received shutdown signal, keeping runner registration (RUNNER_REMOVE_ON_EXIT=false)."
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# Start the runner
echo "Starting GitHub Actions runner..."
exec ./run.sh
