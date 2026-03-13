set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()
INFRA_DIR := ROOT_DIR + "/infra"
DEFAULT_RUNNER_STACK := "runners/github/yocto"
DEFAULT_ARTIFACT_STACK := "services/artifact-server"
RUNNER_ENV_FILE := ROOT_DIR + "/infra/runners/github/yocto/.env"
RUNNER_ENV_EXAMPLE := ROOT_DIR + "/infra/runners/github/yocto/.env.example"
RUST_TOOLCHAIN_FILE := ROOT_DIR + "/apps/rust-toolchain.toml"

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

# Publish local Yocto deploy artifacts into the shared artifact volume.
# This keeps local/manual builds discoverable from the same artifact server.
# Example: just infra::artifact-publish
# Example: just infra::artifact-publish qemux86-64 dev mybuild
artifact-publish machine="qemux86-64" variant="dev" label="" src_dir="":
  @SOURCE_DIR="{{src_dir}}"; \
    if [[ -z "$SOURCE_DIR" ]]; then \
      SOURCE_DIR="{{ROOT_DIR}}/build/yocto/build/{{machine}}-{{variant}}/tmp/deploy/images/{{machine}}"; \
    fi; \
    [[ -d "$SOURCE_DIR" ]] || { echo "missing source artifacts dir: $SOURCE_DIR" >&2; exit 1; }; \
    TAG="{{label}}"; \
    if [[ -z "$TAG" ]]; then TAG="$(date -u +%Y%m%d%H%M%S)"; fi; \
    VOLUME_NAME="yocto-artifacts"; \
    podman volume create "$VOLUME_NAME" >/dev/null; \
    MOUNTPOINT="$(podman volume inspect "$VOLUME_NAME" --format '{{ "{{" }} .Mountpoint {{ "}}" }}')"; \
    DEST_DIR="$MOUNTPOINT/local/{{variant}}/{{machine}}/$TAG"; \
    mkdir -p "$DEST_DIR"; \
    cp -a "$SOURCE_DIR"/. "$DEST_DIR"/; \
    ln -sfn "$TAG" "$MOUNTPOINT/local/{{variant}}/{{machine}}/latest"; \
    echo "Published: $DEST_DIR"; \
    echo "URL: http://localhost:8080/local/{{variant}}/{{machine}}/$TAG/"

# Print URL helper for published artifacts.
artifact-url variant="dev" machine="qemux86-64" label="latest" host="localhost:8080":
  @echo "http://{{host}}/local/{{variant}}/{{machine}}/{{label}}/"

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
