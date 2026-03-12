set shell := ["bash", "-euo", "pipefail", "-c"]

mod rust "just/rust.just"
mod yocto "just/yocto.just"

default:
  @just --list --justfile {{justfile()}}