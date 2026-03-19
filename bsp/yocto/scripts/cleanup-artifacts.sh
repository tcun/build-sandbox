#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_ROOT="${1:-/srv/yocto-artifacts}"
DEV_DAYS="${2:-14}"
TEST_DAYS="${3:-30}"
CANDIDATE_DAYS="${4:-90}"

trim_tree() {
  local path="$1"
  local days="$2"
  if [[ -d "$path" ]]; then
    find "$path" -mindepth 1 -maxdepth 1 -type d -mtime "+$days" -print -exec rm -rf {} +
  fi
}

trim_tree "$ARTIFACT_ROOT/artifacts/dev" "$DEV_DAYS"
trim_tree "$ARTIFACT_ROOT/artifacts/test" "$TEST_DAYS"
trim_tree "$ARTIFACT_ROOT/artifacts/candidates" "$CANDIDATE_DAYS"

echo "Artifact retention cleanup complete."
