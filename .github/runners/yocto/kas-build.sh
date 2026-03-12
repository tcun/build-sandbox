#!/bin/bash
# Helper script to run KAS builds with proper cache configuration
#
# Usage: kas-build.sh <kas-config.yml> [additional kas args]
#
# Environment variables:
#   KAS_BUILD_DIR - Build output directory (default: ./build)
#   DL_DIR        - Download cache (default: /cache/downloads)
#   SSTATE_DIR    - Shared state cache (default: /cache/sstate-cache)

set -e

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <kas-config.yml> [additional kas args]"
    exit 1
fi

KAS_CONFIG="$1"
shift

export KAS_BUILD_DIR="${KAS_BUILD_DIR:-./build}"
export DL_DIR="${DL_DIR:-/cache/downloads}"
export SSTATE_DIR="${SSTATE_DIR:-/cache/sstate-cache}"

echo "=== KAS Build Configuration ==="
echo "Config:      ${KAS_CONFIG}"
echo "Build dir:   ${KAS_BUILD_DIR}"
echo "Downloads:   ${DL_DIR}"
echo "SState:      ${SSTATE_DIR}"
echo "==============================="

exec kas build "${KAS_CONFIG}" "$@"
