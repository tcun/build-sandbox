# Use bash so recipe-local variables behave predictably
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

# Build the selected image/config
build machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"
  export KAS_BUILD_DIR="$BUILD_DIR"
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"
  kas build \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

# Open an interactive kas/bitbake shell
shell machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"
  export KAS_BUILD_DIR="$BUILD_DIR"
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"
  kas shell \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

# Run QEMU for the selected machine/config
run machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"
  export KAS_BUILD_DIR="$BUILD_DIR"
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"
  kas shell --command "runqemu {{machine}} nographic" \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

# Warm repos/build environment without running a full image build
# This uses kas shell to materialize the environment and source checkouts.
fetch machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE:
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"
  export KAS_BUILD_DIR="$BUILD_DIR"
  mkdir -p "$BUILD_DIR" "{{KAS_SOURCES_DIR}}" "{{KAS_DOWNLOAD_DIR}}" "{{KAS_SSTATE_DIR}}"
  kas shell --command "bitbake -p" \
    {{KAS_BASE}}:{{KAS_DIR}}/machine/{{machine}}.yml:{{KAS_DIR}}/distro/{{variant}}.yml:{{KAS_DIR}}/images/{{image}}.yml

# Remove one specific build directory only
clean-build machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT:
  BUILD_DIR="{{YOCTO_ROOT}}/build/{{machine}}-{{variant}}"
  echo "Removing build dir: $BUILD_DIR"
  rm -rf "$BUILD_DIR"

# Remove all build directories, but preserve downloads/sstate/sources
clean-all:
  echo "Removing all Yocto build directories under {{YOCTO_ROOT}}/build"
  rm -rf "{{YOCTO_ROOT}}/build"

# Echo resolved config and paths for debugging/CI
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