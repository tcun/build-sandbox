set shell := ["bash", "-cu"]

KAS_DIR := justfile_directory() / "bsp/yocto/kas"
KAS_BASE := KAS_DIR / "base.yml"

YOCTO_ROOT := justfile_directory() / "build/yocto"
KAS_SOURCES_DIR := YOCTO_ROOT / "sources"
KAS_DOWNLOAD_DIR := YOCTO_ROOT / "downloads"
KAS_SSTATE_DIR := YOCTO_ROOT / "sstate-cache"

DEFAULT_MACHINE := "qemux86-64"
DEFAULT_VARIANT := "dev"
DEFAULT_IMAGE := "minimal"

export KAS_WORK_DIR := justfile_directory()
export KAS_REPO_REF_DIR := KAS_SOURCES_DIR

build machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${VERSION:-0.1.0-alpha}"; \
  BUILD_VERSION_VALUE="${BUILD_VERSION:-$VERSION_VALUE}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  export VERSION="$VERSION_VALUE" BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas build \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

shell machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${VERSION:-0.1.0-alpha}"; \
  BUILD_VERSION_VALUE="${BUILD_VERSION:-$VERSION_VALUE}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  export VERSION="$VERSION_VALUE" BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas shell \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

run machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${VERSION:-0.1.0-alpha}"; \
  BUILD_VERSION_VALUE="${BUILD_VERSION:-$VERSION_VALUE}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  export VERSION="$VERSION_VALUE" BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
  export KAS_BUILD_DIR="$BUILD_DIR"; \
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"; \
  kas shell --command "runqemu {{machine}} nographic" \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

fetch machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  VERSION_VALUE="${VERSION:-0.1.0-alpha}"; \
  BUILD_VERSION_VALUE="${BUILD_VERSION:-$VERSION_VALUE}"; \
  TAR_OPTIONS_VALUE="${TAR_OPTIONS:---no-same-owner}"; \
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"; \
  export VERSION="$VERSION_VALUE" BUILD_VERSION="$BUILD_VERSION_VALUE" TAR_OPTIONS="$TAR_OPTIONS_VALUE"; \
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
  @echo "VERSION=${VERSION:-0.1.0-alpha}"
  @echo "BUILD_VERSION=${BUILD_VERSION:-${VERSION:-0.1.0-alpha}}"
  @echo "TAR_OPTIONS=${TAR_OPTIONS:---no-same-owner}"
