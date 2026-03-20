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

# Update workspace version in apps/Cargo.toml.
set-workspace-version version:
  @VERSION="{{version}}"; \
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
  mv {{APPS_CARGO_TOML}}.tmp {{APPS_CARGO_TOML}}

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

# Validate RC tag format and annotation.
assert-rc-tag tag:
  @TAG="{{tag}}"; \
  TAG="${TAG#refs/tags/}"; \
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then \
    echo "error: candidate tag '$TAG' must match v<major>.<minor>.<patch>-rc.<n>" >&2; \
    exit 1; \
  fi; \
  OBJ_TYPE="$(git -C {{ROOT_DIR}} cat-file -t "$TAG" 2>/dev/null || true)"; \
  if [[ "$OBJ_TYPE" != "tag" ]]; then \
    echo "error: '$TAG' is not an annotated tag" >&2; \
    exit 1; \
  fi; \
  echo "ok: rc tag '$TAG' is annotated and well-formed"

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

# Validate base version input for release-candidate command.
assert-base-version base:
  @BASE="{{base}}"; \
  if [[ "$BASE" == v* ]]; then \
    echo "error: pass base semver without 'v' prefix (example: 1.2.3)" >&2; \
    exit 1; \
  fi; \
  if [[ "$BASE" =~ -rc\.[0-9]+$ ]]; then \
    echo "error: pass base semver only; RC suffix is auto-generated" >&2; \
    exit 1; \
  fi; \
  if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then \
    echo "error: base version '$BASE' must match <major>.<minor>.<patch>" >&2; \
    exit 1; \
  fi

# Require a clean tracked working tree before cutting a release-candidate commit.
assert-clean-working-tree:
  @cd {{ROOT_DIR}}; \
  git diff --quiet || { echo "error: working tree has unstaged changes" >&2; exit 1; }; \
  git diff --cached --quiet || { echo "error: index has staged changes" >&2; exit 1; }

# Compute the next RC tag for a base version (e.g. 1.2.3 -> v1.2.3-rc.4).
next-rc-tag base:
  @BASE="{{base}}"; \
  just --justfile {{ROOT_DIR}}/Justfile git::assert-base-version "$BASE" >/dev/null; \
  MAX_RC=0; \
  while IFS= read -r TAG; do \
    [[ -n "$TAG" ]] || continue; \
    N="${TAG##*-rc.}"; \
    if [[ "$N" =~ ^[0-9]+$ ]] && (( N > MAX_RC )); then \
      MAX_RC="$N"; \
    fi; \
  done < <(git -C {{ROOT_DIR}} tag -l "v${BASE}-rc.*"); \
  NEXT_RC=$((MAX_RC + 1)); \
  echo "v${BASE}-rc.${NEXT_RC}"

# Cut and push the next release-candidate tag for a base version.
# Creates a dedicated release commit even when version is unchanged.
release-candidate-publish base remote="origin":
  @BASE="{{base}}"; \
  REMOTE="{{remote}}"; \
  just --justfile {{ROOT_DIR}}/Justfile git::assert-base-version "$BASE"; \
  just --justfile {{ROOT_DIR}}/Justfile git::assert-clean-working-tree; \
  if ! git -C {{ROOT_DIR}} config --get user.name >/dev/null || ! git -C {{ROOT_DIR}} config --get user.email >/dev/null; then \
    GIT_NAME_VALUE="${GITHUB_ACTOR:-build-sandbox-ci}"; \
    GIT_EMAIL_VALUE="${GITHUB_ACTOR:+${GITHUB_ACTOR}@users.noreply.github.com}"; \
    if [[ -z "$GIT_EMAIL_VALUE" ]]; then GIT_EMAIL_VALUE="build-sandbox-ci@local"; fi; \
    git -C {{ROOT_DIR}} config user.name "$GIT_NAME_VALUE"; \
    git -C {{ROOT_DIR}} config user.email "$GIT_EMAIL_VALUE"; \
    echo "info: configured local git identity for tagging as $GIT_NAME_VALUE <$GIT_EMAIL_VALUE>" >&2; \
  fi; \
  git -C {{ROOT_DIR}} fetch --force --tags "$REMOTE" "+refs/tags/*:refs/tags/*"; \
  RC_TAG="$(just --justfile {{ROOT_DIR}}/Justfile git::next-rc-tag "$BASE")"; \
  RC_VERSION="${RC_TAG#v}"; \
  if git -C {{ROOT_DIR}} rev-parse "$RC_TAG" >/dev/null 2>&1; then \
    echo "error: tag '$RC_TAG' already exists" >&2; \
    exit 1; \
  fi; \
  just --justfile {{ROOT_DIR}}/Justfile git::set-workspace-version "$RC_VERSION"; \
  just --justfile {{ROOT_DIR}}/Justfile rust::check; \
  git -C {{ROOT_DIR}} add apps/Cargo.toml; \
  if [[ -f {{ROOT_DIR}}/apps/Cargo.lock ]]; then \
    git -C {{ROOT_DIR}} add apps/Cargo.lock; \
  fi; \
  git -C {{ROOT_DIR}} commit --allow-empty -m "release: $RC_TAG"; \
  git -C {{ROOT_DIR}} tag -a "$RC_TAG" -m "Release candidate $RC_TAG"; \
  BRANCH="$(git -C {{ROOT_DIR}} symbolic-ref --quiet --short HEAD || true)"; \
  if [[ -z "$BRANCH" ]]; then \
    echo "error: current HEAD is detached; checkout a branch before publishing" >&2; \
    exit 1; \
  fi; \
  git -C {{ROOT_DIR}} push "$REMOTE" "$BRANCH" "$RC_TAG"; \
  echo "RC_TAG=$RC_TAG"; \
  echo "RC_VERSION=$RC_VERSION"; \
  echo "BRANCH=$BRANCH"

# Cut and push a stable release commit and tag from an existing candidate tag.
# Writes the stable version into apps/Cargo.toml, commits on the current branch,
# places the annotated stable tag on that commit, and pushes both.
# Must be run from the branch where the RC commit is HEAD (non-detached).
promote-tag candidate_tag release_version remote="origin":
  @CANDIDATE_TAG_RAW="{{candidate_tag}}"; \
  RELEASE_VERSION_RAW="{{release_version}}"; \
  REMOTE="{{remote}}"; \
  CANDIDATE_TAG="${CANDIDATE_TAG_RAW#refs/tags/}"; \
  RELEASE_VERSION="${RELEASE_VERSION_RAW#v}"; \
  STABLE_TAG="v${RELEASE_VERSION}"; \
  if [[ ! "$CANDIDATE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then \
    echo "error: candidate tag '$CANDIDATE_TAG' must match v<major>.<minor>.<patch>-rc.<n>" >&2; \
    exit 1; \
  fi; \
  if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then \
    echo "error: release version '$RELEASE_VERSION_RAW' must match <major>.<minor>.<patch>" >&2; \
    exit 1; \
  fi; \
  if ! git -C {{ROOT_DIR}} config --get user.name >/dev/null || ! git -C {{ROOT_DIR}} config --get user.email >/dev/null; then \
    GIT_NAME_VALUE="${GITHUB_ACTOR:-build-sandbox-ci}"; \
    GIT_EMAIL_VALUE="${GITHUB_ACTOR:+${GITHUB_ACTOR}@users.noreply.github.com}"; \
    if [[ -z "$GIT_EMAIL_VALUE" ]]; then GIT_EMAIL_VALUE="build-sandbox-ci@local"; fi; \
    git -C {{ROOT_DIR}} config user.name "$GIT_NAME_VALUE"; \
    git -C {{ROOT_DIR}} config user.email "$GIT_EMAIL_VALUE"; \
    echo "info: configured local git identity for tagging as $GIT_NAME_VALUE <$GIT_EMAIL_VALUE>" >&2; \
  fi; \
  BRANCH="$(git -C {{ROOT_DIR}} symbolic-ref --quiet --short HEAD || true)"; \
  if [[ -z "$BRANCH" ]]; then \
    echo "error: current HEAD is detached; checkout the release branch before promoting" >&2; \
    exit 1; \
  fi; \
  just --justfile {{ROOT_DIR}}/Justfile git::assert-clean-working-tree; \
  git -C {{ROOT_DIR}} fetch --force --tags "$REMOTE" "+refs/tags/*:refs/tags/*"; \
  OBJ_TYPE="$(git -C {{ROOT_DIR}} cat-file -t "$CANDIDATE_TAG" 2>/dev/null || true)"; \
  if [[ "$OBJ_TYPE" != "tag" ]]; then \
    echo "error: candidate tag '$CANDIDATE_TAG' must exist and be annotated" >&2; \
    exit 1; \
  fi; \
  CANDIDATE_COMMIT="$(git -C {{ROOT_DIR}} rev-list -n1 "$CANDIDATE_TAG")"; \
  HEAD_COMMIT="$(git -C {{ROOT_DIR}} rev-parse HEAD)"; \
  if [[ "$HEAD_COMMIT" != "$CANDIDATE_COMMIT" ]]; then \
    echo "error: HEAD ($HEAD_COMMIT) does not match the candidate commit ($CANDIDATE_COMMIT)" >&2; \
    echo "       sync '$BRANCH' to the RC commit before promoting" >&2; \
    exit 1; \
  fi; \
  TAG_CREATED="false"; \
  RELEASE_COMMIT=""; \
  if git -C {{ROOT_DIR}} rev-parse "$STABLE_TAG" >/dev/null 2>&1; then \
    STABLE_OBJ_TYPE="$(git -C {{ROOT_DIR}} cat-file -t "$STABLE_TAG" 2>/dev/null || true)"; \
    if [[ "$STABLE_OBJ_TYPE" != "tag" ]]; then \
      echo "error: existing stable tag '$STABLE_TAG' must be annotated" >&2; \
      exit 1; \
    fi; \
    RELEASE_COMMIT="$(git -C {{ROOT_DIR}} rev-list -n1 "$STABLE_TAG")"; \
    STABLE_PARENT="$(git -C {{ROOT_DIR}} log --format=%P -1 "$RELEASE_COMMIT")"; \
    if [[ "$STABLE_PARENT" != "$CANDIDATE_COMMIT" ]]; then \
      echo "error: stable tag '$STABLE_TAG' exists but its parent ($STABLE_PARENT) is not the candidate commit ($CANDIDATE_COMMIT)" >&2; \
      exit 1; \
    fi; \
    echo "info: stable tag '$STABLE_TAG' already promoted from candidate commit" >&2; \
  else \
    just --justfile {{ROOT_DIR}}/Justfile git::set-workspace-version "$RELEASE_VERSION"; \
    just --justfile {{ROOT_DIR}}/Justfile rust::check; \
    git -C {{ROOT_DIR}} add apps/Cargo.toml; \
    if [[ -f {{ROOT_DIR}}/apps/Cargo.lock ]]; then \
      git -C {{ROOT_DIR}} add apps/Cargo.lock; \
    fi; \
    git -C {{ROOT_DIR}} commit -m "release: $STABLE_TAG"; \
    RELEASE_COMMIT="$(git -C {{ROOT_DIR}} rev-parse HEAD)"; \
    git -C {{ROOT_DIR}} tag -a "$STABLE_TAG" -m "Release $STABLE_TAG (promoted from $CANDIDATE_TAG)"; \
    git -C {{ROOT_DIR}} push "$REMOTE" "$BRANCH" "$STABLE_TAG"; \
    TAG_CREATED="true"; \
  fi; \
  echo "STABLE_TAG=$STABLE_TAG"; \
  echo "CANDIDATE_COMMIT=$CANDIDATE_COMMIT"; \
  echo "RELEASE_COMMIT=$RELEASE_COMMIT"; \
  echo "TAG_CREATED=$TAG_CREATED"
