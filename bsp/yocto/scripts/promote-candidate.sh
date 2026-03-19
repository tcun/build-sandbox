#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  promote-candidate.sh \
    --artifact-root <dir> \
    --candidate-tag <vX.Y.Z-rc.N> \
    --release-tag <vX.Y.Z> \
    --machine <machine> \
    [--candidate-commit <sha>]
USAGE
}

ARTIFACT_ROOT="/srv/yocto-artifacts"
CANDIDATE_TAG=""
RELEASE_TAG=""
MACHINE=""
CANDIDATE_COMMIT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-root)
      ARTIFACT_ROOT="$2"
      shift 2
      ;;
    --candidate-tag)
      CANDIDATE_TAG="$2"
      shift 2
      ;;
    --release-tag)
      RELEASE_TAG="$2"
      shift 2
      ;;
    --machine)
      MACHINE="$2"
      shift 2
      ;;
    --candidate-commit)
      CANDIDATE_COMMIT="$2"
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

[[ -n "$CANDIDATE_TAG" ]] || { echo "error: --candidate-tag is required" >&2; exit 2; }
[[ -n "$RELEASE_TAG" ]] || { echo "error: --release-tag is required" >&2; exit 2; }
[[ -n "$MACHINE" ]] || { echo "error: --machine is required" >&2; exit 2; }

if [[ ! "$CANDIDATE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then
  echo "error: candidate tag '$CANDIDATE_TAG' must match v<major>.<minor>.<patch>-rc.<n>" >&2
  exit 1
fi
if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: release tag '$RELEASE_TAG' must match v<major>.<minor>.<patch>" >&2
  exit 1
fi

CANDIDATE_DIR="$ARTIFACT_ROOT/artifacts/candidates/$CANDIDATE_TAG/$MACHINE"
RELEASE_ROOT="$ARTIFACT_ROOT/artifacts/releases/$RELEASE_TAG"
RELEASE_DIR="$RELEASE_ROOT/$MACHINE"
STAGING_DIR="$ARTIFACT_ROOT/artifacts/releases/.staging/${RELEASE_TAG}-${MACHINE}-$(date -u +%Y%m%d%H%M%S)-$$"

[[ -d "$CANDIDATE_DIR" ]] || { echo "error: candidate artifact dir missing: $CANDIDATE_DIR" >&2; exit 1; }
[[ -f "$CANDIDATE_DIR/checksums.txt" ]] || { echo "error: missing checksums.txt in candidate dir" >&2; exit 1; }
[[ -f "$CANDIDATE_DIR/manifest.json" ]] || { echo "error: missing manifest.json in candidate dir" >&2; exit 1; }

if [[ -z "$CANDIDATE_COMMIT" ]]; then
  CANDIDATE_COMMIT="$(jq -r '.commit_sha // .resolved_commit // empty' "$CANDIDATE_DIR/manifest.json")"
fi

(
  cd "$CANDIDATE_DIR"
  sha256sum -c checksums.txt
)

if [[ -d "$RELEASE_DIR" ]]; then
  [[ -f "$RELEASE_DIR/checksums.txt" ]] || { echo "error: release dir exists but checksums.txt is missing" >&2; exit 1; }
  [[ -f "$RELEASE_DIR/manifest.json" ]] || { echo "error: release dir exists but manifest.json is missing" >&2; exit 1; }

  if ! cmp -s "$CANDIDATE_DIR/checksums.txt" "$RELEASE_DIR/checksums.txt"; then
    echo "error: release path already exists with different checksums" >&2
    exit 1
  fi

  (
    cd "$RELEASE_DIR"
    sha256sum -c checksums.txt
  )
else
  mkdir -p "$(dirname "$STAGING_DIR")"

  cleanup() {
    if [[ -d "$STAGING_DIR" ]]; then
      rm -rf "$STAGING_DIR"
    fi
  }
  trap cleanup EXIT

  mkdir -p "$STAGING_DIR"
  cp -a "$CANDIDATE_DIR"/. "$STAGING_DIR"/

  [[ -f "$STAGING_DIR/checksums.txt" ]] || { echo "error: staging checksums.txt missing after copy" >&2; exit 1; }
  [[ -f "$STAGING_DIR/manifest.json" ]] || { echo "error: staging manifest.json missing after copy" >&2; exit 1; }

  (
    cd "$STAGING_DIR"
    sha256sum -c checksums.txt
  )

  CANDIDATE_LIST="$(mktemp)"
  STAGING_LIST="$(mktemp)"
  trap 'rm -f "$CANDIDATE_LIST" "$STAGING_LIST"; cleanup' EXIT

  (
    cd "$CANDIDATE_DIR"
    find . -type f | sort
  ) > "$CANDIDATE_LIST"

  (
    cd "$STAGING_DIR"
    find . -type f | sort
  ) > "$STAGING_LIST"

  if ! diff -u "$CANDIDATE_LIST" "$STAGING_LIST" >/dev/null; then
    echo "error: staging file inventory does not match candidate" >&2
    exit 1
  fi

  mkdir -p "$RELEASE_ROOT"
  mv "$STAGING_DIR" "$RELEASE_DIR"

  trap - EXIT
  rm -f "$CANDIDATE_LIST" "$STAGING_LIST"
fi

mkdir -p "$RELEASE_ROOT"
PROMOTION_FILE="$RELEASE_ROOT/promotion.json"
TMP_PROMOTION="${PROMOTION_FILE}.tmp"
PROMOTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -f "$PROMOTION_FILE" ]]; then
  jq \
    --arg stable_tag "$RELEASE_TAG" \
    --arg candidate_tag "$CANDIDATE_TAG" \
    --arg candidate_commit "$CANDIDATE_COMMIT" \
    --arg machine "$MACHINE" \
    --arg promoted_at "$PROMOTED_AT" \
    --arg release_path "artifacts/releases/$RELEASE_TAG/$MACHINE" \
    --arg candidate_path "artifacts/candidates/$CANDIDATE_TAG/$MACHINE" \
    '.stable_tag = $stable_tag
     | .candidate_tag = $candidate_tag
     | .candidate_commit = $candidate_commit
     | .release_path = $release_path
     | .candidate_path = $candidate_path
     | .promoted_at = $promoted_at
     | .machines = ((.machines // []) + [$machine] | unique)' \
    "$PROMOTION_FILE" > "$TMP_PROMOTION"
else
  jq -n \
    --arg stable_tag "$RELEASE_TAG" \
    --arg candidate_tag "$CANDIDATE_TAG" \
    --arg candidate_commit "$CANDIDATE_COMMIT" \
    --arg machine "$MACHINE" \
    --arg promoted_at "$PROMOTED_AT" \
    --arg release_path "artifacts/releases/$RELEASE_TAG/$MACHINE" \
    --arg candidate_path "artifacts/candidates/$CANDIDATE_TAG/$MACHINE" \
    '{
      stable_tag: $stable_tag,
      candidate_tag: $candidate_tag,
      candidate_commit: $candidate_commit,
      promoted_at: $promoted_at,
      release_path: $release_path,
      candidate_path: $candidate_path,
      machines: [$machine]
    }' > "$TMP_PROMOTION"
fi

mv "$TMP_PROMOTION" "$PROMOTION_FILE"

echo "RELEASE_DIR=$RELEASE_DIR"
echo "PROMOTION_FILE=$PROMOTION_FILE"
