ROOT_DIR := justfile_directory()
APPS_DIR := ROOT_DIR + "/apps"

# Versions / environment
status:
  cd {{APPS_DIR}} && rustc --version
  cd {{APPS_DIR}} && cargo --version
  just --version

# Formatting
fmt:
  cd {{APPS_DIR}} && cargo fmt --all

fmt-check:
  cd {{APPS_DIR}} && cargo fmt --all --check

# Analysis
check:
  cd {{APPS_DIR}} && cargo check --workspace --all-targets

clippy:
  cd {{APPS_DIR}} && cargo clippy --workspace --all-targets --all-features -- -D warnings

# Tests
test:
  cd {{APPS_DIR}} && cargo test --workspace --all-features

# Builds
build:
  cd {{APPS_DIR}} && cargo build --workspace

build-release:
  cd {{APPS_DIR}} && cargo build --workspace --release

run:
  cd {{APPS_DIR}} && cargo run -p smoke-core

run-release:
  cd {{APPS_DIR}} && cargo run -p smoke-core --release

# Lockfile / dependency helpers
update:
  cd {{APPS_DIR}} && cargo update

tree:
  cd {{APPS_DIR}} && cargo tree

# Main workflows
dev: fmt check test
ci: fmt-check check clippy test build-release