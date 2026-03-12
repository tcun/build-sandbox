set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()
INFRA_DIR := ROOT_DIR + "/infra"
DEFAULT_RUNNER_STACK := "runners/github/yocto"
DEFAULT_ARTIFACT_STACK := "services/artifact-server"

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
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-up stack="{{stack}}" build="{{build}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-up stack="{{DEFAULT_RUNNER_STACK}}" build="true"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-up stack="{{DEFAULT_ARTIFACT_STACK}}" build="false"; \
    fi

# Stop both default local stacks, or one selected stack.
down stack="":
  @if [[ -n "{{stack}}" ]]; then \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-down stack="{{stack}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-down stack="{{DEFAULT_ARTIFACT_STACK}}"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-down stack="{{DEFAULT_RUNNER_STACK}}"; \
    fi

# Show ps for both default local stacks, or one selected stack.
ps stack="":
  @if [[ -n "{{stack}}" ]]; then \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-ps stack="{{stack}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-ps stack="{{DEFAULT_RUNNER_STACK}}"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-ps stack="{{DEFAULT_ARTIFACT_STACK}}"; \
    fi

# Show logs for both default local stacks, or one selected stack.
logs stack="" tail="200" follow="false":
  @if [[ -n "{{stack}}" ]]; then \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-logs stack="{{stack}}" tail="{{tail}}" follow="{{follow}}"; \
    else \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-logs stack="{{DEFAULT_RUNNER_STACK}}" tail="{{tail}}" follow="{{follow}}"; \
      just --justfile {{ROOT_DIR}}/Justfile infra::stack-logs stack="{{DEFAULT_ARTIFACT_STACK}}" tail="{{tail}}" follow="{{follow}}"; \
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
