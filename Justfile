set shell := ["bash", "-euo", "pipefail", "-c"]

mod rust "just/rust.just"
mod yocto "just/yocto.just"
mod qemu "just/qemu.just"
mod git "just/git.just"
mod ci "just/ci.just"
mod infra "just/infra.just"

default:
  @just --list --justfile {{justfile()}}

# Local developer build profile.
build-dev machine="qemux86-64":
  @REQUESTED_REF="$(git -C {{justfile_directory()}} symbolic-ref --quiet --short HEAD || echo detached-head)"; \
    RESOLVED_COMMIT="$(git -C {{justfile_directory()}} rev-parse HEAD)"; \
    just ci::build-profile "dev" "{{machine}}" "$REQUESTED_REF" "$RESOLVED_COMMIT" "false"

# Local validation build profile (canonical source rules + test gates).
build-test machine="qemux86-64" simulator="true":
  @REQUESTED_REF="$(git -C {{justfile_directory()}} symbolic-ref --quiet --short HEAD || echo detached-head)"; \
    RESOLVED_COMMIT="$(git -C {{justfile_directory()}} rev-parse HEAD)"; \
    just ci::build-profile "test" "{{machine}}" "$REQUESTED_REF" "$RESOLVED_COMMIT" "{{simulator}}"

# Cut and push the next release-candidate tag for a base version.
# Example: just release-candidate 1.2.3
release-candidate base_version remote="origin":
  @just git::release-candidate-publish "{{base_version}}" "{{remote}}"
