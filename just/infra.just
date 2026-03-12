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
