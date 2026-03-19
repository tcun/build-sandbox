set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()
YOCTO_TEST_GATES_SCRIPT := ROOT_DIR + "/bsp/yocto/scripts/test-gates.sh"
PSEUDO_ENV_SANITIZE := "unset PSEUDO_DISABLED PSEUDO_PREFIX PSEUDO_LOCALSTATEDIR PSEUDO_PASSWD FAKEROOTKEY"

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

# Build dev/test profiles with explicit ref and commit metadata.
build-profile profile machine="qemux86-64" requested_ref="" resolved_commit="" run_simulator="true":
  @cd {{ROOT_DIR}}; \
    PROFILE="{{profile}}"; \
    MACHINE="{{machine}}"; \
    REQUESTED_REF="{{requested_ref}}"; \
    RESOLVED_COMMIT="{{resolved_commit}}"; \
    RUN_SIMULATOR="{{run_simulator}}"; \
    just ci::guard-no-private-keys; \
    case "$PROFILE" in \
      dev|test) ;; \
      *) echo "error: profile must be dev or test" >&2; exit 1 ;; \
    esac; \
    if [[ -z "$REQUESTED_REF" ]]; then REQUESTED_REF="${GITHUB_REF_NAME:-local}"; fi; \
    if [[ -z "$RESOLVED_COMMIT" ]]; then RESOLVED_COMMIT="$(git rev-parse HEAD)"; fi; \
    SOURCE_BRANCH_VALUE="$REQUESTED_REF"; \
    if [[ "$SOURCE_BRANCH_VALUE" =~ ^[0-9a-f]{7,40}$ || "$SOURCE_BRANCH_VALUE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then \
      SOURCE_BRANCH_VALUE="$(git for-each-ref --format='%(refname:short)' --contains "$RESOLVED_COMMIT" refs/remotes/origin | sed -n 's#^origin/##p' | head -n1 || true)"; \
    fi; \
    if [[ -z "$SOURCE_BRANCH_VALUE" ]]; then SOURCE_BRANCH_VALUE="main"; fi; \
    SHORT_SHA="$(git rev-parse --short=7 "$RESOLVED_COMMIT")"; \
    {{PSEUDO_ENV_SANITIZE}}; \
    VERSION="0.0.0-${PROFILE}"; \
    BUILD_VERSION="${VERSION}+g${SHORT_SHA}"; \
    echo "PROFILE=$PROFILE"; \
    echo "REQUESTED_REF=$REQUESTED_REF"; \
    echo "RESOLVED_COMMIT=$RESOLVED_COMMIT"; \
    echo "SOURCE_BRANCH=$SOURCE_BRANCH_VALUE"; \
    echo "VERSION=$VERSION"; \
    echo "BUILD_VERSION=$BUILD_VERSION"; \
    if [[ "$PROFILE" == "dev" ]]; then \
      just rust::check; \
      TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" just yocto::build "$MACHINE" dev minimal; \
    else \
      just rust::ci; \
      TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$RESOLVED_COMMIT" just yocto::preflight-source "$MACHINE" test minimal; \
      TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$RESOLVED_COMMIT" just yocto::build "$MACHINE" test minimal; \
      TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$RESOLVED_COMMIT" RUN_SIMULATOR="$RUN_SIMULATOR" "{{YOCTO_TEST_GATES_SCRIPT}}" "$MACHINE" test minimal; \
    fi

# Canonical release-candidate pipeline for an RC tag.
release-candidate tag="" machine="qemux86-64":
  @cd {{ROOT_DIR}}; \
    TAG="{{tag}}"; \
    MACHINE="{{machine}}"; \
    just ci::guard-no-private-keys; \
    if [[ -z "$TAG" ]]; then TAG="${GITHUB_REF_NAME:-}"; fi; \
    [[ -n "$TAG" ]] || { echo "error: missing RC tag (pass explicitly or set GITHUB_REF_NAME)" >&2; exit 1; }; \
    just git::assert-rc-tag "$TAG"; \
    just git::assert-tag-matches-workspace "$TAG"; \
    eval "$(just git::release-env "$TAG")"; \
    {{PSEUDO_ENV_SANITIZE}}; \
    SOURCE_REV="$(git rev-parse HEAD)"; \
    SOURCE_BRANCH_VALUE="$(git for-each-ref --format='%(refname:short)' --contains "$SOURCE_REV" refs/remotes/origin | sed -n 's#^origin/##p' | head -n1 || true)"; \
    if [[ -z "$SOURCE_BRANCH_VALUE" ]]; then SOURCE_BRANCH_VALUE="main"; fi; \
    echo "TAG=$TAG"; \
    echo "VERSION=$VERSION"; \
    echo "BUILD_VERSION=$BUILD_VERSION"; \
    echo "SOURCE_REV=$SOURCE_REV"; \
    echo "SOURCE_BRANCH=$SOURCE_BRANCH_VALUE"; \
    just rust::ci; \
    TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$SOURCE_REV" just yocto::preflight-source "$MACHINE" release minimal; \
    TEMPLATE_VERSION="$VERSION" TEMPLATE_BUILD_VERSION="$BUILD_VERSION" SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$SOURCE_REV" just yocto::build "$MACHINE" release minimal

# Canonical Yocto test build used by push/PR quality gates.
yocto-test machine="qemux86-64":
  @cd {{ROOT_DIR}}; \
    REQUESTED_REF="${GITHUB_REF_NAME:-main}"; \
    RESOLVED_COMMIT="$(git rev-parse HEAD)"; \
    just ci::build-profile test "{{machine}}" "$REQUESTED_REF" "$RESOLVED_COMMIT" "true"

# Promote candidate artifacts to a stable release (no rebuild).
promote-candidate candidate_tag release_version machine="qemux86-64" remote="origin":
  @cd {{ROOT_DIR}}; \
    CANDIDATE_TAG="{{candidate_tag}}"; \
    RELEASE_VERSION="{{release_version}}"; \
    MACHINE="{{machine}}"; \
    REMOTE="{{remote}}"; \
    just ci::guard-no-private-keys; \
    TAG_OUT="$(just git::promote-tag "$CANDIDATE_TAG" "$RELEASE_VERSION" "$REMOTE")"; \
    eval "$TAG_OUT"; \
    [[ -n "${STABLE_TAG:-}" ]] || { echo "error: missing STABLE_TAG from git::promote-tag" >&2; exit 1; }; \
    [[ -n "${CANDIDATE_COMMIT:-}" ]] || { echo "error: missing CANDIDATE_COMMIT from git::promote-tag" >&2; exit 1; }; \
    PROMOTE_OUT="$(just infra::artifact-promote-candidate "$CANDIDATE_TAG" "$STABLE_TAG" "$MACHINE" "$CANDIDATE_COMMIT")"; \
    URL_VALUE="$(echo "$PROMOTE_OUT" | awk -F= '/^URL=/{print $2; exit}')"; \
    echo "$PROMOTE_OUT"; \
    echo "STABLE_TAG=$STABLE_TAG"; \
    echo "CANDIDATE_COMMIT=$CANDIDATE_COMMIT"; \
    echo "PROMOTION_URL=$URL_VALUE"
