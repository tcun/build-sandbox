set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()
APPS_CARGO_TOML := ROOT_DIR + "/apps/Cargo.toml"
DEFAULT_BASE_VERSION := "0.1.0-alpha"

# Print VERSION and BUILD_VERSION as KEY=VALUE lines suitable for eval.
version-env base=DEFAULT_BASE_VERSION:
  @DESC="$(git -C {{ROOT_DIR}} describe --tags --match 'v*' --long --abbrev=7 2>/dev/null || true)"; \
  SHA="$(git -C {{ROOT_DIR}} rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"; \
  VERSION="{{base}}"; \
  BUILD_VERSION="${VERSION}+g${SHA}"; \
  if [[ "$DESC" =~ ^v(.+)-([0-9]+)-g([0-9a-f]+)$ ]]; then \
    VERSION="${BASH_REMATCH[1]}"; \
    DIST="${BASH_REMATCH[2]}"; \
    GIT_SHA="${BASH_REMATCH[3]}"; \
    BUILD_VERSION="${VERSION}+${DIST}.g${GIT_SHA}"; \
  fi; \
  echo "VERSION=$VERSION"; \
  echo "BUILD_VERSION=$BUILD_VERSION"

# Print only VERSION.
version base=DEFAULT_BASE_VERSION:
  @eval "$(just --justfile {{ROOT_DIR}}/Justfile git::version-env {{base}})"; \
  echo "$VERSION"

# Print only BUILD_VERSION.
build-version base=DEFAULT_BASE_VERSION:
  @eval "$(just --justfile {{ROOT_DIR}}/Justfile git::version-env {{base}})"; \
  echo "$BUILD_VERSION"

# Print the workspace Cargo version from apps/Cargo.toml.
workspace-version:
  @awk ' \
    BEGIN { in_ws = 0 } \
    /^\[workspace\.package\]/ { in_ws = 1; next } \
    /^\[/ && in_ws { in_ws = 0 } \
    in_ws && $1 == "version" && $2 == "=" { \
      gsub(/"/, "", $3); \
      print $3; \
      exit \
    } \
  ' {{APPS_CARGO_TOML}}

# Validate that the provided release tag matches workspace Cargo version and is annotated.
assert-tag-matches-workspace tag="":
  @TAG="{{tag}}"; \
  if [[ -z "$TAG" ]]; then \
    TAG="${GITHUB_REF_NAME:-}"; \
  fi; \
  if [[ -z "$TAG" ]]; then \
    echo "error: missing tag. pass one explicitly or set GITHUB_REF_NAME" >&2; \
    exit 1; \
  fi; \
  TAG="${TAG#refs/tags/}"; \
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then \
    echo "error: tag '$TAG' is not a valid semver tag with 'v' prefix" >&2; \
    exit 1; \
  fi; \
  OBJ_TYPE="$(git -C {{ROOT_DIR}} cat-file -t "$TAG" 2>/dev/null || true)"; \
  if [[ "$OBJ_TYPE" != "tag" ]]; then \
    echo "error: '$TAG' is not an annotated tag" >&2; \
    exit 1; \
  fi; \
  TAG_VERSION="${TAG#v}"; \
  WORKSPACE_VERSION="$(just --justfile {{ROOT_DIR}}/Justfile git::workspace-version)"; \
  if [[ "$TAG_VERSION" != "$WORKSPACE_VERSION" ]]; then \
    echo "error: tag version '$TAG_VERSION' != workspace version '$WORKSPACE_VERSION'" >&2; \
    exit 1; \
  fi; \
  echo "ok: tag '$TAG' matches workspace version '$WORKSPACE_VERSION'"

# Print VERSION and BUILD_VERSION derived from an explicit release tag.
release-env tag="":
  @TAG="{{tag}}"; \
  if [[ -z "$TAG" ]]; then \
    TAG="${GITHUB_REF_NAME:-}"; \
  fi; \
  if [[ -z "$TAG" ]]; then \
    echo "error: missing tag. pass one explicitly or set GITHUB_REF_NAME" >&2; \
    exit 1; \
  fi; \
  TAG="${TAG#refs/tags/}"; \
  VERSION="${TAG#v}"; \
  SHA="$(git -C {{ROOT_DIR}} rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"; \
  BUILD_VERSION="${VERSION}+0.g${SHA}"; \
  echo "VERSION=$VERSION"; \
  echo "BUILD_VERSION=$BUILD_VERSION"

# Update workspace version, commit, and create an annotated tag.
# Example: just git::cut v0.1.0-alpha
cut tag:
  @TAG="{{tag}}"; \
  if [[ "$TAG" != v* ]]; then \
    TAG="v$TAG"; \
  fi; \
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then \
    echo "error: tag '$TAG' is not valid semver with 'v' prefix" >&2; \
    exit 1; \
  fi; \
  if git -C {{ROOT_DIR}} rev-parse "$TAG" >/dev/null 2>&1; then \
    echo "error: tag '$TAG' already exists" >&2; \
    exit 1; \
  fi; \
  VERSION="${TAG#v}"; \
  awk -v version="$VERSION" ' \
    BEGIN { in_ws = 0 } \
    /^\[workspace\.package\]/ { in_ws = 1; print; next } \
    /^\[/ && in_ws { in_ws = 0 } \
    in_ws && $1 == "version" && $2 == "=" { \
      print "version = \"" version "\""; \
      next \
    } \
    { print } \
  ' {{APPS_CARGO_TOML}} > {{APPS_CARGO_TOML}}.tmp; \
  mv {{APPS_CARGO_TOML}}.tmp {{APPS_CARGO_TOML}}; \
  git -C {{ROOT_DIR}} add apps/Cargo.toml; \
  if git -C {{ROOT_DIR}} diff --cached --quiet; then \
    echo "info: workspace version already '$VERSION'"; \
  else \
    git -C {{ROOT_DIR}} commit -m "release: $TAG"; \
  fi; \
  git -C {{ROOT_DIR}} tag -a "$TAG" -m "Release $TAG"; \
  echo "created annotated tag $TAG"

# Cut a release and push branch+annotated tag to remote.
# Example: just git::publish v0.1.0-alpha
publish tag remote="origin":
  @TAG="{{tag}}"; \
  if [[ "$TAG" != v* ]]; then \
    TAG="v$TAG"; \
  fi; \
  just --justfile {{ROOT_DIR}}/Justfile git::cut "$TAG"; \
  BRANCH="$(git -C {{ROOT_DIR}} symbolic-ref --quiet --short HEAD)"; \
  git -C {{ROOT_DIR}} push "{{remote}}" "$BRANCH" --follow-tags; \
  echo "pushed branch '$BRANCH' and annotated tags to '{{remote}}'"
