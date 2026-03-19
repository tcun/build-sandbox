set shell := ["bash", "-euo", "pipefail", "-c"]

KAS_DIR := justfile_directory() / "bsp/yocto/kas"
KAS_BASE := KAS_DIR / "base.yml"
YOCTO_PREFLIGHT_SCRIPT := justfile_directory() / "bsp/yocto/scripts/preflight-source.sh"

YOCTO_ROOT := env_var_or_default("YOCTO_ROOT", justfile_directory() / "build/yocto")
KAS_SOURCES_DIR := YOCTO_ROOT / "sources"
KAS_DOWNLOAD_DIR := YOCTO_ROOT / "downloads"
KAS_SSTATE_DIR := YOCTO_ROOT / "sstate-cache"
PSEUDO_ENV_SANITIZE := "unset PSEUDO_DISABLED PSEUDO_PREFIX PSEUDO_LOCALSTATEDIR PSEUDO_PASSWD FAKEROOTKEY"

DEFAULT_MACHINE := "qemux86-64"
DEFAULT_VARIANT := "dev"
DEFAULT_IMAGE := "minimal"

export KAS_WORK_DIR := justfile_directory()
export KAS_REPO_REF_DIR := KAS_SOURCES_DIR

build machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${TEMPLATE_VERSION:-${VERSION:-0.1.0-alpha}}"; \
  BUILD_VERSION_VALUE="${TEMPLATE_BUILD_VERSION:-${BUILD_VERSION:-$VERSION_VALUE}}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  SOURCE_BRANCH_VALUE="${SOURCE_BRANCH:-main}"; \
  SOURCE_REV_VALUE="${SOURCE_REV:-}"; \
  SMOKE_CORE_EXTERNALSRC_VALUE="${SMOKE_CORE_EXTERNALSRC:-{{justfile_directory()}}}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  if [[ "{{variant}}" == "dev" ]]; then \
    [[ "$SMOKE_CORE_EXTERNALSRC_VALUE" = /* ]] || { echo "SMOKE_CORE_EXTERNALSRC must be an absolute path for dev builds" >&2; exit 1; }; \
    [[ -d "$SMOKE_CORE_EXTERNALSRC_VALUE" ]] || { echo "SMOKE_CORE_EXTERNALSRC path does not exist: $SMOKE_CORE_EXTERNALSRC_VALUE" >&2; exit 1; }; \
    if [[ -z "$SOURCE_REV_VALUE" && -d "$SMOKE_CORE_EXTERNALSRC_VALUE/.git" ]]; then \
      SOURCE_REV_VALUE="$(git -C "$SMOKE_CORE_EXTERNALSRC_VALUE" rev-parse HEAD)"; \
    fi; \
  else \
    SMOKE_CORE_EXTERNALSRC_VALUE=""; \
    [[ -n "$SOURCE_REV_VALUE" ]] || { echo "SOURCE_REV is required for variant '{{variant}}'" >&2; exit 1; }; \
  fi; \
  {{PSEUDO_ENV_SANITIZE}}; \
  export TEMPLATE_VERSION="$VERSION_VALUE" TEMPLATE_BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  unset VERSION BUILD_VERSION; \
  export SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$SOURCE_REV_VALUE" SMOKE_CORE_EXTERNALSRC="$SMOKE_CORE_EXTERNALSRC_VALUE"; \
  export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} TEMPLATE_VERSION TEMPLATE_BUILD_VERSION TAR_OPTIONS SOURCE_BRANCH SOURCE_REV SMOKE_CORE_EXTERNALSRC GIT_SSH_COMMAND"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas build \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

preflight-source machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${TEMPLATE_VERSION:-${VERSION:-0.1.0-alpha}}"; \
  BUILD_VERSION_VALUE="${TEMPLATE_BUILD_VERSION:-${BUILD_VERSION:-$VERSION_VALUE}}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  SOURCE_BRANCH_VALUE="${SOURCE_BRANCH:-main}"; \
  SOURCE_REV_VALUE="${SOURCE_REV:-}"; \
  SMOKE_CORE_EXTERNALSRC_VALUE="${SMOKE_CORE_EXTERNALSRC:-{{justfile_directory()}}}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  if [[ "{{variant}}" == "dev" ]]; then \
    [[ "$SMOKE_CORE_EXTERNALSRC_VALUE" = /* ]] || { echo "SMOKE_CORE_EXTERNALSRC must be an absolute path for dev builds" >&2; exit 1; }; \
    [[ -d "$SMOKE_CORE_EXTERNALSRC_VALUE" ]] || { echo "SMOKE_CORE_EXTERNALSRC path does not exist: $SMOKE_CORE_EXTERNALSRC_VALUE" >&2; exit 1; }; \
    if [[ -z "$SOURCE_REV_VALUE" && -d "$SMOKE_CORE_EXTERNALSRC_VALUE/.git" ]]; then \
      SOURCE_REV_VALUE="$(git -C "$SMOKE_CORE_EXTERNALSRC_VALUE" rev-parse HEAD)"; \
    fi; \
  else \
    SMOKE_CORE_EXTERNALSRC_VALUE=""; \
    [[ -n "$SOURCE_REV_VALUE" ]] || { echo "SOURCE_REV is required for variant '{{variant}}'" >&2; exit 1; }; \
  fi; \
  {{PSEUDO_ENV_SANITIZE}}; \
  export TEMPLATE_VERSION="$VERSION_VALUE" TEMPLATE_BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  unset VERSION BUILD_VERSION; \
  export SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$SOURCE_REV_VALUE" SMOKE_CORE_EXTERNALSRC="$SMOKE_CORE_EXTERNALSRC_VALUE"; \
  export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} TEMPLATE_VERSION TEMPLATE_BUILD_VERSION TAR_OPTIONS SOURCE_BRANCH SOURCE_REV SMOKE_CORE_EXTERNALSRC GIT_SSH_COMMAND"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas shell --command "bash {{YOCTO_PREFLIGHT_SCRIPT}} {{variant}}" \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

shell machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${TEMPLATE_VERSION:-${VERSION:-0.1.0-alpha}}"; \
  BUILD_VERSION_VALUE="${TEMPLATE_BUILD_VERSION:-${BUILD_VERSION:-$VERSION_VALUE}}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  SOURCE_BRANCH_VALUE="${SOURCE_BRANCH:-main}"; \
  SOURCE_REV_VALUE="${SOURCE_REV:-}"; \
  SMOKE_CORE_EXTERNALSRC_VALUE="${SMOKE_CORE_EXTERNALSRC:-{{justfile_directory()}}}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  if [[ "{{variant}}" == "dev" ]]; then \
    [[ "$SMOKE_CORE_EXTERNALSRC_VALUE" = /* ]] || { echo "SMOKE_CORE_EXTERNALSRC must be an absolute path for dev builds" >&2; exit 1; }; \
    [[ -d "$SMOKE_CORE_EXTERNALSRC_VALUE" ]] || { echo "SMOKE_CORE_EXTERNALSRC path does not exist: $SMOKE_CORE_EXTERNALSRC_VALUE" >&2; exit 1; }; \
    if [[ -z "$SOURCE_REV_VALUE" && -d "$SMOKE_CORE_EXTERNALSRC_VALUE/.git" ]]; then \
      SOURCE_REV_VALUE="$(git -C "$SMOKE_CORE_EXTERNALSRC_VALUE" rev-parse HEAD)"; \
    fi; \
  else \
    SMOKE_CORE_EXTERNALSRC_VALUE=""; \
    [[ -n "$SOURCE_REV_VALUE" ]] || { echo "SOURCE_REV is required for variant '{{variant}}'" >&2; exit 1; }; \
  fi; \
  {{PSEUDO_ENV_SANITIZE}}; \
  export TEMPLATE_VERSION="$VERSION_VALUE" TEMPLATE_BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  unset VERSION BUILD_VERSION; \
  export SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$SOURCE_REV_VALUE" SMOKE_CORE_EXTERNALSRC="$SMOKE_CORE_EXTERNALSRC_VALUE"; \
  export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} TEMPLATE_VERSION TEMPLATE_BUILD_VERSION TAR_OPTIONS SOURCE_BRANCH SOURCE_REV SMOKE_CORE_EXTERNALSRC GIT_SSH_COMMAND"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas shell \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

run machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${TEMPLATE_VERSION:-${VERSION:-0.1.0-alpha}}"; \
  BUILD_VERSION_VALUE="${TEMPLATE_BUILD_VERSION:-${BUILD_VERSION:-$VERSION_VALUE}}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  SOURCE_BRANCH_VALUE="${SOURCE_BRANCH:-main}"; \
  SOURCE_REV_VALUE="${SOURCE_REV:-}"; \
  SMOKE_CORE_EXTERNALSRC_VALUE="${SMOKE_CORE_EXTERNALSRC:-{{justfile_directory()}}}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  if [[ "{{variant}}" == "dev" ]]; then \
    [[ "$SMOKE_CORE_EXTERNALSRC_VALUE" = /* ]] || { echo "SMOKE_CORE_EXTERNALSRC must be an absolute path for dev builds" >&2; exit 1; }; \
    [[ -d "$SMOKE_CORE_EXTERNALSRC_VALUE" ]] || { echo "SMOKE_CORE_EXTERNALSRC path does not exist: $SMOKE_CORE_EXTERNALSRC_VALUE" >&2; exit 1; }; \
    if [[ -z "$SOURCE_REV_VALUE" && -d "$SMOKE_CORE_EXTERNALSRC_VALUE/.git" ]]; then \
      SOURCE_REV_VALUE="$(git -C "$SMOKE_CORE_EXTERNALSRC_VALUE" rev-parse HEAD)"; \
    fi; \
  else \
    SMOKE_CORE_EXTERNALSRC_VALUE=""; \
    [[ -n "$SOURCE_REV_VALUE" ]] || { echo "SOURCE_REV is required for variant '{{variant}}'" >&2; exit 1; }; \
  fi; \
  {{PSEUDO_ENV_SANITIZE}}; \
  export TEMPLATE_VERSION="$VERSION_VALUE" TEMPLATE_BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  unset VERSION BUILD_VERSION; \
  export SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$SOURCE_REV_VALUE" SMOKE_CORE_EXTERNALSRC="$SMOKE_CORE_EXTERNALSRC_VALUE"; \
  export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} TEMPLATE_VERSION TEMPLATE_BUILD_VERSION TAR_OPTIONS SOURCE_BRANCH SOURCE_REV SMOKE_CORE_EXTERNALSRC GIT_SSH_COMMAND"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas shell --command "runqemu {{machine}} nographic" \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

fetch machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${TEMPLATE_VERSION:-${VERSION:-0.1.0-alpha}}"; \
  BUILD_VERSION_VALUE="${TEMPLATE_BUILD_VERSION:-${BUILD_VERSION:-$VERSION_VALUE}}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  SOURCE_BRANCH_VALUE="${SOURCE_BRANCH:-main}"; \
  SOURCE_REV_VALUE="${SOURCE_REV:-}"; \
  SMOKE_CORE_EXTERNALSRC_VALUE="${SMOKE_CORE_EXTERNALSRC:-{{justfile_directory()}}}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  if [[ "{{variant}}" == "dev" ]]; then \
    [[ "$SMOKE_CORE_EXTERNALSRC_VALUE" = /* ]] || { echo "SMOKE_CORE_EXTERNALSRC must be an absolute path for dev builds" >&2; exit 1; }; \
    [[ -d "$SMOKE_CORE_EXTERNALSRC_VALUE" ]] || { echo "SMOKE_CORE_EXTERNALSRC path does not exist: $SMOKE_CORE_EXTERNALSRC_VALUE" >&2; exit 1; }; \
    if [[ -z "$SOURCE_REV_VALUE" && -d "$SMOKE_CORE_EXTERNALSRC_VALUE/.git" ]]; then \
      SOURCE_REV_VALUE="$(git -C "$SMOKE_CORE_EXTERNALSRC_VALUE" rev-parse HEAD)"; \
    fi; \
  else \
    SMOKE_CORE_EXTERNALSRC_VALUE=""; \
    [[ -n "$SOURCE_REV_VALUE" ]] || { echo "SOURCE_REV is required for variant '{{variant}}'" >&2; exit 1; }; \
  fi; \
  {{PSEUDO_ENV_SANITIZE}}; \
  export TEMPLATE_VERSION="$VERSION_VALUE" TEMPLATE_BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  unset VERSION BUILD_VERSION; \
  export SOURCE_BRANCH="$SOURCE_BRANCH_VALUE" SOURCE_REV="$SOURCE_REV_VALUE" SMOKE_CORE_EXTERNALSRC="$SMOKE_CORE_EXTERNALSRC_VALUE"; \
  export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} TEMPLATE_VERSION TEMPLATE_BUILD_VERSION TAR_OPTIONS SOURCE_BRANCH SOURCE_REV SMOKE_CORE_EXTERNALSRC GIT_SSH_COMMAND"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas shell --command "bitbake -p" \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

clean-build machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT:
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  echo "Removing build dir: $BUILD_DIR"; \
  rm -rf "$BUILD_DIR"

clean-all:
  echo "Removing all Yocto build directories under {{YOCTO_ROOT}}/build"
  rm -rf "{{YOCTO_ROOT}}/build"

print-config machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  @echo "KAS_BASE={{KAS_BASE}}"
  @echo "KAS_DIR={{KAS_DIR}}"
  @echo "YOCTO_ROOT={{YOCTO_ROOT}}"
  @echo "machine={{machine}}"
  @echo "variant={{variant}}"
  @echo "image={{image}}"
  @echo "KAS_MACHINE_FILE={{KAS_DIR}}/machine/{{machine}}.yml"
  @echo "KAS_DISTRO_FILE={{KAS_DIR}}/distro/{{variant}}.yml"
  @echo "KAS_IMAGE_FILE={{KAS_DIR}}/images/{{image}}.yml"
  @echo "KAS_WORK_DIR={{justfile_directory()}}"
  @echo "KAS_BUILD_DIR={{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"
  @echo "KAS_SOURCES_DIR={{KAS_SOURCES_DIR}}"
  @echo "KAS_DOWNLOAD_DIR={{KAS_DOWNLOAD_DIR}}"
  @echo "KAS_SSTATE_DIR={{KAS_SSTATE_DIR}}"
  @echo "TEMPLATE_VERSION=${TEMPLATE_VERSION:-${VERSION:-0.1.0-alpha}}"
  @echo "TEMPLATE_BUILD_VERSION=${TEMPLATE_BUILD_VERSION:-${BUILD_VERSION:-${TEMPLATE_VERSION:-${VERSION:-0.1.0-alpha}}}}"
  @echo "TAR_OPTIONS=${TAR_OPTIONS:---no-same-owner}"
  @echo "SOURCE_BRANCH=${SOURCE_BRANCH:-main}"
  @echo "SOURCE_REV=${SOURCE_REV:-}"
  @echo "SMOKE_CORE_EXTERNALSRC=${SMOKE_CORE_EXTERNALSRC:-{{justfile_directory()}}}"
