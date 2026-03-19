#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  publish-artifacts.sh \
    --source-dir <dir> \
    --dest-dir <dir> \
    --build-profile <dev|test|release|candidate> \
    --machine <machine> \
    --requested-ref <ref> \
    --resolved-commit <sha> \
    [--candidate-tag-or-ref <value>] \
    [--branch-or-ref <value>] \
    [--workflow-run-id <id>] \
    [--yocto-profile <profile>] \
    [--rust-workspace-version <version>] \
    [--runner-image-or-version <value>]
USAGE
}

SOURCE_DIR=""
DEST_DIR=""
BUILD_PROFILE=""
MACHINE=""
REQUESTED_REF=""
RESOLVED_COMMIT=""
CANDIDATE_TAG_OR_REF=""
BRANCH_OR_REF=""
WORKFLOW_RUN_ID=""
YOCTO_PROFILE=""
RUST_WORKSPACE_VERSION=""
RUNNER_IMAGE_OR_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --dest-dir)
      DEST_DIR="$2"
      shift 2
      ;;
    --build-profile)
      BUILD_PROFILE="$2"
      shift 2
      ;;
    --machine)
      MACHINE="$2"
      shift 2
      ;;
    --requested-ref)
      REQUESTED_REF="$2"
      shift 2
      ;;
    --resolved-commit)
      RESOLVED_COMMIT="$2"
      shift 2
      ;;
    --candidate-tag-or-ref)
      CANDIDATE_TAG_OR_REF="$2"
      shift 2
      ;;
    --branch-or-ref)
      BRANCH_OR_REF="$2"
      shift 2
      ;;
    --workflow-run-id)
      WORKFLOW_RUN_ID="$2"
      shift 2
      ;;
    --yocto-profile)
      YOCTO_PROFILE="$2"
      shift 2
      ;;
    --rust-workspace-version)
      RUST_WORKSPACE_VERSION="$2"
      shift 2
      ;;
    --runner-image-or-version)
      RUNNER_IMAGE_OR_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -n "$SOURCE_DIR" ]] || { echo "error: --source-dir is required" >&2; exit 2; }
[[ -n "$DEST_DIR" ]] || { echo "error: --dest-dir is required" >&2; exit 2; }
[[ -n "$BUILD_PROFILE" ]] || { echo "error: --build-profile is required" >&2; exit 2; }
[[ -n "$MACHINE" ]] || { echo "error: --machine is required" >&2; exit 2; }
[[ -n "$REQUESTED_REF" ]] || { echo "error: --requested-ref is required" >&2; exit 2; }
[[ -n "$RESOLVED_COMMIT" ]] || { echo "error: --resolved-commit is required" >&2; exit 2; }
[[ -d "$SOURCE_DIR" ]] || { echo "error: source dir not found: $SOURCE_DIR" >&2; exit 1; }

if [[ -e "$DEST_DIR" ]]; then
  echo "error: destination already exists: $DEST_DIR" >&2
  echo "       refusing to overwrite immutable artifact path" >&2
  exit 1
fi

if [[ -z "$CANDIDATE_TAG_OR_REF" ]]; then
  CANDIDATE_TAG_OR_REF="$REQUESTED_REF"
fi
if [[ -z "$BRANCH_OR_REF" ]]; then
  BRANCH_OR_REF="$REQUESTED_REF"
fi
if [[ -z "$YOCTO_PROFILE" ]]; then
  YOCTO_PROFILE="$BUILD_PROFILE"
fi
if [[ -z "$RUNNER_IMAGE_OR_VERSION" ]]; then
  RUNNER_IMAGE_OR_VERSION="${RUNNER_IMAGE:-${RUNNER_VERSION:-unknown}}"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
if [[ -z "$RUST_WORKSPACE_VERSION" ]]; then
  RUST_WORKSPACE_VERSION="$(awk '
    BEGIN { in_ws = 0 }
    /^\[workspace\.package\]/ { in_ws = 1; next }
    /^\[/ && in_ws { in_ws = 0 }
    in_ws && $1 == "version" && $2 == "=" {
      gsub(/"/, "", $3)
      print $3
      exit
    }
  ' "$REPO_ROOT/apps/Cargo.toml")"
fi

BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DEST_PARENT="$(dirname "$DEST_DIR")"
mkdir -p "$DEST_PARENT"

STAGING_DIR="${DEST_DIR}.staging.$(date -u +%Y%m%d%H%M%S).$$"
cleanup() {
  if [[ -d "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR"
cp -a "$SOURCE_DIR"/. "$STAGING_DIR"/

(
  cd "$STAGING_DIR"
  : > checksums.txt
  while IFS= read -r -d '' file; do
    rel="${file#./}"
    sha256sum "$rel" >> checksums.txt
  done < <(find . -type f ! -name checksums.txt ! -name manifest.json -print0 | sort -z)
)

ARTIFACTS_JSON="$(jq -Rn '
  [inputs
   | select(length > 0)
   | capture("(?<sha256>[0-9a-f]{64})  (?<path>.+)")
   | {path: .path, sha256: .sha256}]
' < "$STAGING_DIR/checksums.txt")"

jq -n \
  --arg requested_ref "$REQUESTED_REF" \
  --arg resolved_commit "$RESOLVED_COMMIT" \
  --arg candidate_tag_or_ref "$CANDIDATE_TAG_OR_REF" \
  --arg build_profile "$BUILD_PROFILE" \
  --arg commit_sha "$RESOLVED_COMMIT" \
  --arg branch_or_ref "$BRANCH_OR_REF" \
  --arg workflow_run_id "$WORKFLOW_RUN_ID" \
  --arg machine "$MACHINE" \
  --arg yocto_profile "$YOCTO_PROFILE" \
  --arg rust_workspace_version "$RUST_WORKSPACE_VERSION" \
  --arg runner_image_or_version "$RUNNER_IMAGE_OR_VERSION" \
  --arg build_timestamp "$BUILD_TIMESTAMP" \
  --arg source_rev "$RESOLVED_COMMIT" \
  --argjson artifact_files "$ARTIFACTS_JSON" \
  '{
    schema_version: 1,
    requested_ref: $requested_ref,
    resolved_commit: $resolved_commit,
    candidate_tag_or_ref: $candidate_tag_or_ref,
    build_profile: $build_profile,
    commit_sha: $commit_sha,
    branch_or_ref: $branch_or_ref,
    workflow_run_id: $workflow_run_id,
    machine: $machine,
    yocto_profile: $yocto_profile,
    rust_workspace_version: $rust_workspace_version,
    source_revisions: {
      smoke_core: $source_rev
    },
    runner_image_or_version: $runner_image_or_version,
    artifact_files_with_sha256: $artifact_files,
    build_timestamp: $build_timestamp
  }' > "$STAGING_DIR/manifest.json"

mv "$STAGING_DIR" "$DEST_DIR"
trap - EXIT

echo "PUBLISHED_DIR=$DEST_DIR"
