set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()
INFRA_DIR := ROOT_DIR + "/infra"
DEFAULT_RUNNER_STACK := "runners/github/yocto"
DEFAULT_ARTIFACT_STACK := "services/artifact-server"
RUNNER_ENV_FILE := ROOT_DIR + "/infra/runners/github/yocto/.env"
RUNNER_ENV_EXAMPLE := ROOT_DIR + "/infra/runners/github/yocto/.env.example"
RUST_TOOLCHAIN_FILE := ROOT_DIR + "/apps/rust-toolchain.toml"
ARTIFACT_PUBLISH_SCRIPT := ROOT_DIR + "/bsp/yocto/scripts/publish-artifacts.sh"
ARTIFACT_PROMOTE_SCRIPT := ROOT_DIR + "/bsp/yocto/scripts/promote-candidate.sh"
ARTIFACT_RETENTION_SCRIPT := ROOT_DIR + "/bsp/yocto/scripts/cleanup-artifacts.sh"

# Generic: start one compose stack under infra/.
# Example: just infra::stack-up stack=runners/github/yocto build=true
stack-up stack=DEFAULT_RUNNER_STACK build="false":
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    STACK_DIR="{{INFRA_DIR}}/{{stack}}"; \
    [[ -f "$STACK_DIR/compose.yaml" ]] || { echo "missing compose.yaml in $STACK_DIR" >&2; exit 1; }; \
    BUILD_ARGS=(); \
    if [[ "{{build}}" == "true" ]]; then BUILD_ARGS+=(--build); fi; \
    cd "$STACK_DIR" && "${COMPOSE[@]}" up -d "${BUILD_ARGS[@]}"

# Generic: stop one compose stack under infra/.
stack-down stack=DEFAULT_RUNNER_STACK:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    STACK_DIR="{{INFRA_DIR}}/{{stack}}"; \
    [[ -f "$STACK_DIR/compose.yaml" ]] || { echo "missing compose.yaml in $STACK_DIR" >&2; exit 1; }; \
    cd "$STACK_DIR" && "${COMPOSE[@]}" down

# Generic: ps for one compose stack under infra/.
stack-ps stack=DEFAULT_RUNNER_STACK:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    STACK_DIR="{{INFRA_DIR}}/{{stack}}"; \
    [[ -f "$STACK_DIR/compose.yaml" ]] || { echo "missing compose.yaml in $STACK_DIR" >&2; exit 1; }; \
    cd "$STACK_DIR" && "${COMPOSE[@]}" ps

# Generic: logs for one compose stack under infra/.
stack-logs stack=DEFAULT_RUNNER_STACK tail="200" follow="false":
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    STACK_DIR="{{INFRA_DIR}}/{{stack}}"; \
    [[ -f "$STACK_DIR/compose.yaml" ]] || { echo "missing compose.yaml in $STACK_DIR" >&2; exit 1; }; \
    FOLLOW_ARGS=(); \
    if [[ "{{follow}}" == "true" ]]; then FOLLOW_ARGS+=(-f); fi; \
    cd "$STACK_DIR" && "${COMPOSE[@]}" logs --tail="{{tail}}" "${FOLLOW_ARGS[@]}"

# Start both default local stacks, or one selected stack.
# Example: just infra::up
# Example: just infra::up stack=services/artifact-server
up stack="" build="true":
  @if [[ -n "{{stack}}" ]]; then \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-up "{{stack}}" "{{build}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-up "{{DEFAULT_RUNNER_STACK}}" "true"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-up "{{DEFAULT_ARTIFACT_STACK}}" "false"; \
    fi

# Stop both default local stacks, or one selected stack.
down stack="":
  @if [[ -n "{{stack}}" ]]; then \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-down "{{stack}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-down "{{DEFAULT_ARTIFACT_STACK}}"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-down "{{DEFAULT_RUNNER_STACK}}"; \
    fi

# Show ps for both default local stacks, or one selected stack.
ps stack="":
  @if [[ -n "{{stack}}" ]]; then \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-ps "{{stack}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-ps "{{DEFAULT_RUNNER_STACK}}"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-ps "{{DEFAULT_ARTIFACT_STACK}}"; \
    fi

# Show logs for both default local stacks, or one selected stack.
logs stack="" tail="200" follow="false":
  @if [[ -n "{{stack}}" ]]; then \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-logs "{{stack}}" "{{tail}}" "{{follow}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-logs "{{DEFAULT_RUNNER_STACK}}" "{{tail}}" "{{follow}}"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-logs "{{DEFAULT_ARTIFACT_STACK}}" "{{tail}}" "{{follow}}"; \
    fi

# Publish build artifacts into standardized profile paths.
# Profiles:
# - dev:        artifacts/dev/<ref>/<sha>/<machine>/
# - test:       artifacts/test/<ref>/<run-id>/<machine>/
# - candidate:  artifacts/candidates/<candidate-tag>/<machine>/
artifact-publish-profile profile machine="qemux86-64" requested_ref="" resolved_commit="" workflow_run_id="" branch_or_ref="" candidate_tag="" src_dir="" artifact_root="":
  @PROFILE="{{profile}}"; \
    MACHINE="{{machine}}"; \
    REQUESTED_REF="{{requested_ref}}"; \
    RESOLVED_COMMIT="{{resolved_commit}}"; \
    WORKFLOW_RUN_ID="{{workflow_run_id}}"; \
    BRANCH_OR_REF="{{branch_or_ref}}"; \
    CANDIDATE_TAG="{{candidate_tag}}"; \
    SOURCE_DIR="{{src_dir}}"; \
    ARTIFACT_ROOT_VALUE="{{artifact_root}}"; \
    if [[ -z "$ARTIFACT_ROOT_VALUE" ]]; then ARTIFACT_ROOT_VALUE="${ARTIFACT_ROOT:-/srv/yocto-artifacts}"; fi; \
    mkdir -p "$ARTIFACT_ROOT_VALUE"; \
    [[ -w "$ARTIFACT_ROOT_VALUE" ]] || { echo "artifact root is not writable: $ARTIFACT_ROOT_VALUE" >&2; exit 1; }; \
    if [[ -z "$REQUESTED_REF" ]]; then REQUESTED_REF="${GITHUB_REF_NAME:-local}"; fi; \
    if [[ -z "$RESOLVED_COMMIT" ]]; then RESOLVED_COMMIT="$(git -C {{ROOT_DIR}} rev-parse HEAD)"; fi; \
    if [[ -z "$BRANCH_OR_REF" ]]; then BRANCH_OR_REF="$REQUESTED_REF"; fi; \
    SAFE_REF="$(echo "$REQUESTED_REF" | tr '/:@' '_' | tr -cd '[:alnum:]._-')"; \
    if [[ -z "$SAFE_REF" ]]; then SAFE_REF="detached"; fi; \
    case "$PROFILE" in \
      dev) \
        VARIANT="dev"; \
        if [[ -z "$SOURCE_DIR" ]]; then SOURCE_DIR="{{ROOT_DIR}}/build/yocto/build/${MACHINE}-${VARIANT}/tmp/deploy/images/${MACHINE}"; fi; \
        DEST_REL="artifacts/dev/${SAFE_REF}/${RESOLVED_COMMIT}/${MACHINE}"; \
        CANDIDATE_OR_REF="$REQUESTED_REF"; \
        YOCTO_PROFILE="dev"; \
        ;; \
      test) \
        VARIANT="test"; \
        if [[ -z "$SOURCE_DIR" ]]; then SOURCE_DIR="{{ROOT_DIR}}/build/yocto/build/${MACHINE}-${VARIANT}/tmp/deploy/images/${MACHINE}"; fi; \
        if [[ -z "$WORKFLOW_RUN_ID" ]]; then WORKFLOW_RUN_ID="${GITHUB_RUN_ID:-$(date -u +%Y%m%d%H%M%S)}"; fi; \
        DEST_REL="artifacts/test/${SAFE_REF}/${WORKFLOW_RUN_ID}/${MACHINE}"; \
        CANDIDATE_OR_REF="$REQUESTED_REF"; \
        YOCTO_PROFILE="test"; \
        ;; \
      candidate) \
        VARIANT="release"; \
        if [[ -z "$SOURCE_DIR" ]]; then SOURCE_DIR="{{ROOT_DIR}}/build/yocto/build/${MACHINE}-${VARIANT}/tmp/deploy/images/${MACHINE}"; fi; \
        if [[ -z "$CANDIDATE_TAG" ]]; then CANDIDATE_TAG="$REQUESTED_REF"; fi; \
        [[ "$CANDIDATE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || { echo "candidate_tag must match v<major>.<minor>.<patch>-rc.<n>" >&2; exit 1; }; \
        DEST_REL="artifacts/candidates/${CANDIDATE_TAG}/${MACHINE}"; \
        CANDIDATE_OR_REF="$CANDIDATE_TAG"; \
        YOCTO_PROFILE="release"; \
        ;; \
      *) \
        echo "error: unsupported profile '$PROFILE' (expected dev|test|candidate)" >&2; \
        exit 1; \
        ;; \
    esac; \
    [[ -d "$SOURCE_DIR" ]] || { echo "missing source artifacts dir: $SOURCE_DIR" >&2; exit 1; }; \
    DEST_DIR="$ARTIFACT_ROOT_VALUE/$DEST_REL"; \
    RUST_WORKSPACE_VERSION="$(just --justfile {{ROOT_DIR}}/Justfile git::workspace-version)"; \
    RUNNER_IMAGE_OR_VERSION="${RUNNER_IMAGE:-${RUNNER_VERSION:-unknown}}"; \
    "{{ARTIFACT_PUBLISH_SCRIPT}}" \
      --source-dir "$SOURCE_DIR" \
      --dest-dir "$DEST_DIR" \
      --build-profile "$PROFILE" \
      --machine "$MACHINE" \
      --requested-ref "$REQUESTED_REF" \
      --resolved-commit "$RESOLVED_COMMIT" \
      --candidate-tag-or-ref "$CANDIDATE_OR_REF" \
      --branch-or-ref "$BRANCH_OR_REF" \
      --workflow-run-id "$WORKFLOW_RUN_ID" \
      --yocto-profile "$YOCTO_PROFILE" \
      --rust-workspace-version "$RUST_WORKSPACE_VERSION" \
      --runner-image-or-version "$RUNNER_IMAGE_OR_VERSION"; \
    HOST_VALUE="${ARTIFACT_HOST:-localhost:8080}"; \
    echo "DEST_REL=$DEST_REL"; \
    echo "URL=http://${HOST_VALUE}/${DEST_REL}/"

# Promote candidate artifacts to stable release path with atomic copy and checksum verification.
artifact-promote-candidate candidate_tag release_tag machine="qemux86-64" candidate_commit="" artifact_root="":
  @CANDIDATE_TAG="{{candidate_tag}}"; \
    RELEASE_TAG="{{release_tag}}"; \
    MACHINE="{{machine}}"; \
    CANDIDATE_COMMIT="{{candidate_commit}}"; \
    ARTIFACT_ROOT_VALUE="{{artifact_root}}"; \
    if [[ -z "$ARTIFACT_ROOT_VALUE" ]]; then ARTIFACT_ROOT_VALUE="${ARTIFACT_ROOT:-/srv/yocto-artifacts}"; fi; \
    [[ -w "$ARTIFACT_ROOT_VALUE" ]] || { echo "artifact root is not writable: $ARTIFACT_ROOT_VALUE" >&2; exit 1; }; \
    ARGS=( \
      --artifact-root "$ARTIFACT_ROOT_VALUE" \
      --candidate-tag "$CANDIDATE_TAG" \
      --release-tag "$RELEASE_TAG" \
      --machine "$MACHINE" \
    ); \
    if [[ -n "$CANDIDATE_COMMIT" ]]; then \
      ARGS+=(--candidate-commit "$CANDIDATE_COMMIT"); \
    fi; \
    "{{ARTIFACT_PROMOTE_SCRIPT}}" "${ARGS[@]}"; \
    HOST_VALUE="${ARTIFACT_HOST:-localhost:8080}"; \
    echo "URL=http://${HOST_VALUE}/artifacts/releases/${RELEASE_TAG}/${MACHINE}/"

# Apply retention policy for non-release artifact trees.
artifact-retention dev_days="14" test_days="30" candidate_days="90" artifact_root="":
  @ARTIFACT_ROOT_VALUE="{{artifact_root}}"; \
    if [[ -z "$ARTIFACT_ROOT_VALUE" ]]; then ARTIFACT_ROOT_VALUE="${ARTIFACT_ROOT:-/srv/yocto-artifacts}"; fi; \
    "{{ARTIFACT_RETENTION_SCRIPT}}" "$ARTIFACT_ROOT_VALUE" "{{dev_days}}" "{{test_days}}" "{{candidate_days}}"

# Print URL helper for relative artifact paths.
artifact-url path host="localhost:8080":
  @REL_PATH="{{path}}"; \
    REL_PATH="${REL_PATH#/}"; \
    [[ -n "$REL_PATH" ]] || { echo "error: path is required" >&2; exit 1; }; \
    echo "http://{{host}}/${REL_PATH}/"

# Convenience aliases for default runner/artifact stacks.
runner-up:
  @just --justfile {{ROOT_DIR}}/Justfile infra::runner-env-sync
  @just --justfile {{ROOT_DIR}}/Justfile infra::runner-env-validate
  @just --justfile {{ROOT_DIR}}/Justfile infra::up "runners/github/yocto" "true"

runner-down:
  @just --justfile {{ROOT_DIR}}/Justfile infra::down "runners/github/yocto"

runner-logs tail="200" follow="false":
  @just --justfile {{ROOT_DIR}}/Justfile infra::logs "runners/github/yocto" "{{tail}}" "{{follow}}"

artifact-up:
  @just --justfile {{ROOT_DIR}}/Justfile infra::up "services/artifact-server" "false"

artifact-down:
  @just --justfile {{ROOT_DIR}}/Justfile infra::down "services/artifact-server"

artifact-logs tail="200" follow="false":
  @just --justfile {{ROOT_DIR}}/Justfile infra::logs "services/artifact-server" "{{tail}}" "{{follow}}"

# Sync runner .env defaults from workspace/toolchain metadata.
# - Creates infra/runners/github/yocto/.env from .env.example if missing
# - Sets RUST_VERSION from apps/rust-toolchain.toml if available
runner-env-sync:
  @ENV_FILE="{{RUNNER_ENV_FILE}}"; \
    EXAMPLE="{{RUNNER_ENV_EXAMPLE}}"; \
    TOOLCHAIN="{{RUST_TOOLCHAIN_FILE}}"; \
    if [[ ! -f "$ENV_FILE" ]]; then \
      cp "$EXAMPLE" "$ENV_FILE"; \
      echo "Created $ENV_FILE from example"; \
    fi; \
    RUST_VER="$(awk -F'\"' '/^[[:space:]]*channel[[:space:]]*=[[:space:]]*\"/{print $2; exit}' "$TOOLCHAIN" 2>/dev/null || true)"; \
    if [[ -n "$RUST_VER" ]]; then \
      if grep -q '^RUST_VERSION=' "$ENV_FILE"; then \
        sed -i "s/^RUST_VERSION=.*/RUST_VERSION=$RUST_VER/" "$ENV_FILE"; \
      else \
        echo "RUST_VERSION=$RUST_VER" >> "$ENV_FILE"; \
      fi; \
      echo "Set RUST_VERSION=$RUST_VER in $ENV_FILE"; \
    else \
      echo "WARN: could not parse Rust channel from $TOOLCHAIN"; \
    fi

# Validate runner env before booting the stack.
runner-env-validate:
  @ENV_FILE="{{RUNNER_ENV_FILE}}"; \
    [[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE (run just infra::runner-env-sync)" >&2; exit 1; }; \
    RUNNER_TOKEN_VAL="$(awk -F= '/^RUNNER_TOKEN=/{print $2; exit}' "$ENV_FILE" || true)"; \
    RUNNER_REPO_VAL="$(awk -F= '/^RUNNER_REPO=/{print $2; exit}' "$ENV_FILE" || true)"; \
    RUNNER_RECONFIGURE_VAL="$(awk -F= '/^RUNNER_RECONFIGURE=/{print $2; exit}' "$ENV_FILE" || true)"; \
    if [[ "$RUNNER_TOKEN_VAL" == "your_token_here" ]]; then RUNNER_TOKEN_VAL=""; fi; \
    if [[ -z "$RUNNER_RECONFIGURE_VAL" ]]; then RUNNER_RECONFIGURE_VAL="false"; fi; \
    [[ -n "$RUNNER_REPO_VAL" ]] || { echo "RUNNER_REPO is required in $ENV_FILE (owner/repo or org)" >&2; exit 1; }; \
    if [[ "$RUNNER_RECONFIGURE_VAL" == "true" && -z "$RUNNER_TOKEN_VAL" ]]; then \
      echo "RUNNER_TOKEN is required when RUNNER_RECONFIGURE=true in $ENV_FILE." >&2; \
      exit 1; \
    fi; \
    if [[ -z "$RUNNER_TOKEN_VAL" ]]; then \
      echo "WARN: RUNNER_TOKEN is empty. This is fine only if runner is already configured in the existing container." >&2; \
    fi; \
    echo "Runner env validation passed for $RUNNER_REPO_VAL"
