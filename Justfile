set shell := ["bash", "-euo", "pipefail", "-c"]

mod rust "just/rust.just"

default:
  @just --list --justfile {{justfile()}}