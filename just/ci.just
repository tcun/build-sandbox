set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()

# Prevent accidental leakage of private deploy keys into git history.
guard-no-private-keys:
  @cd {{ROOT_DIR}}; \
    TRACKED="$(git ls-files 'infra/runners/github/yocto/keys/*' | grep -Ev '\.pub$' || true)"; \
    if [[ -n "$TRACKED" ]]; then \
      echo "error: tracked private key files detected:" >&2; \
      echo "$TRACKED" >&2; \
      exit 1; \
    fi

# Fast baseline checks for local and PR validation.
preflight:
  @cd {{ROOT_DIR}}; \
    just ci::guard-no-private-keys; \
    eval "$(just git::version-env)"; \
    echo "VERSION=$VERSION"; \
    echo "BUILD_VERSION=$BUILD_VERSION"; \
    just rust::fmt-check; \
    just rust::check; \
    just rust::test

# Full release pipeline for a tagged commit.
release tag="":
  @cd {{ROOT_DIR}}; \
    just ci::guard-no-private-keys; \
    git fetch --force --tags origin "+refs/tags/*:refs/tags/*"; \
    just git::assert-tag-matches-workspace "{{tag}}"; \
    eval "$(just git::release-env "{{tag}}")"; \
    SOURCE_REV="$(git rev-parse HEAD)"; \
    echo "VERSION=$VERSION"; \
    echo "BUILD_VERSION=$BUILD_VERSION"; \
    echo "SOURCE_REV=$SOURCE_REV"; \
    just rust::ci; \
    TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_REV="$SOURCE_REV" just yocto::preflight-source qemux86-64 release minimal; \
    TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_REV="$SOURCE_REV" just yocto::build qemux86-64 release minimal

# Canonical Yocto test build for smoke-core source policy verification.
yocto-test:
  @cd {{ROOT_DIR}}; \
    just ci::guard-no-private-keys; \
    eval "$(just git::version-env)"; \
    SOURCE_REV="$(git rev-parse HEAD)"; \
    echo "VERSION=$VERSION"; \
    echo "BUILD_VERSION=$BUILD_VERSION"; \
    echo "SOURCE_REV=$SOURCE_REV"; \
    TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_REV="$SOURCE_REV" just yocto::preflight-source qemux86-64 test minimal; \
    TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_REV="$SOURCE_REV" just yocto::build qemux86-64 test minimal
