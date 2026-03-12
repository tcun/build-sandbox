set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()
RUNNER_DIR := ROOT_DIR + "/infra/runners/github/yocto"
ARTIFACT_DIR := ROOT_DIR + "/infra/services/artifact-server"

# Start both local stacks for quick testing.
up:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{RUNNER_DIR}} && "${COMPOSE[@]}" up -d --build; \
    cd {{ARTIFACT_DIR}} && "${COMPOSE[@]}" up -d

# Stop both local stacks.
down:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{ARTIFACT_DIR}} && "${COMPOSE[@]}" down; \
    cd {{RUNNER_DIR}} && "${COMPOSE[@]}" down

# Show status for both stacks.
ps:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{RUNNER_DIR}} && "${COMPOSE[@]}" ps; \
    cd {{ARTIFACT_DIR}} && "${COMPOSE[@]}" ps

# Tail logs for both stacks.
logs:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{RUNNER_DIR}} && "${COMPOSE[@]}" logs --tail=200; \
    cd {{ARTIFACT_DIR}} && "${COMPOSE[@]}" logs --tail=200

runner-up:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{RUNNER_DIR}} && "${COMPOSE[@]}" up -d --build

runner-down:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{RUNNER_DIR}} && "${COMPOSE[@]}" down

runner-logs:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{RUNNER_DIR}} && "${COMPOSE[@]}" logs --tail=200

artifact-up:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{ARTIFACT_DIR}} && "${COMPOSE[@]}" up -d

artifact-down:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{ARTIFACT_DIR}} && "${COMPOSE[@]}" down

artifact-logs:
  @if command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose); else COMPOSE=(podman compose); fi; \
    cd {{ARTIFACT_DIR}} && "${COMPOSE[@]}" logs --tail=200
