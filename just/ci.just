set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()

# Fast baseline checks for local and PR validation.
preflight:
  @cd {{ROOT_DIR}}; \
    eval "$(just git::version-env)"; \
    echo "VERSION=$VERSION"; \
    echo "BUILD_VERSION=$BUILD_VERSION"; \
    just rust::fmt-check; \
    just rust::check; \
    just rust::test

# Full release pipeline for a tagged commit.
release tag="":
  @cd {{ROOT_DIR}}; \
    git fetch --force --tags origin "+refs/tags/*:refs/tags/*"; \
    just git::assert-tag-matches-workspace "{{tag}}"; \
    eval "$(just git::release-env "{{tag}}")"; \
    SOURCE_REV="$(git rev-parse HEAD)"; \
    echo "VERSION=$VERSION"; \
    echo "BUILD_VERSION=$BUILD_VERSION"; \
    echo "SOURCE_REV=$SOURCE_REV"; \
    just rust::ci; \
    VERSION="$VERSION" BUILD_VERSION="$BUILD_VERSION" SOURCE_REV="$SOURCE_REV" just yocto::build variant=release
