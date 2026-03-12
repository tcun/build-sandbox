set shell := ["bash", "-euo", "pipefail", "-c"]

mod rust "just/rust.just"
mod yocto "just/yocto.just"
mod git "just/git.just"
mod ci "just/ci.just"
mod infra "just/infra.just"

default:
  @just --list --justfile {{justfile()}}

# Prepare a release commit/tag, then push branch and tag(s).
# Usage: just release v0.1.0-alpha
release tag:
  @just git::publish "{{tag}}"

# Local-only release cut without pushing.
release-local tag:
  @just git::cut "{{tag}}"
