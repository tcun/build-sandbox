set shell := ["bash", "-euo", "pipefail", "-c"]

ROOT_DIR := justfile_directory()
KAS_DIR := ROOT_DIR + "/bsp/yocto/kas"
ENV_CONTRACT_SCRIPT := ROOT_DIR + "/bsp/yocto/scripts/env-contract.sh"

DEFAULT_MACHINE := "qemux86-64"
DEFAULT_VARIANT := "dev"
DEFAULT_IMAGE := "minimal"

# Print resolved QEMU/runqemu inputs for a Yocto build output.
print-config machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE image_target="":
  @eval "$("{{ENV_CONTRACT_SCRIPT}}" print --mode auto --machine "{{machine}}" --variant "{{variant}}")"; \
    TARGET="{{image_target}}"; \
    if [[ -z "$TARGET" ]]; then \
      TARGET="$(awk '$1=="target:"{print $2; exit}' "{{KAS_DIR}}/images/{{image}}.yml")"; \
    fi; \
    [[ -n "$TARGET" ]] || { echo "error: unable to resolve image target for image={{image}}" >&2; exit 1; }; \
    CONF_LINK="$DEPLOY_DIR/${TARGET}-{{machine}}.rootfs.qemuboot.conf"; \
    if [[ -f "$CONF_LINK" ]]; then \
      CONF="$CONF_LINK"; \
    else \
      CONF="$(ls -1t "$DEPLOY_DIR"/"${TARGET}"-"{{machine}}".rootfs-*.qemuboot.conf 2>/dev/null | head -n1 || true)"; \
    fi; \
    [[ -n "$CONF" ]] || { echo "error: qemuboot config not found under $DEPLOY_DIR" >&2; exit 1; }; \
    echo "POKY_INIT=$POKY_INIT"; \
    echo "BUILD_DIR=$BUILD_DIR"; \
    echo "DEPLOY_DIR=$DEPLOY_DIR"; \
    echo "IMAGE_TARGET=$TARGET"; \
    echo "QEMUBOOT_CONF=$CONF"

# Run image in QEMU via Poky's runqemu.
# Example:
#   just qemu::run
#   just qemu::run qemux86-64 dev minimal "" true
run machine=DEFAULT_MACHINE variant=DEFAULT_VARIANT image=DEFAULT_IMAGE image_target="" nographic="true":
  @eval "$("{{ENV_CONTRACT_SCRIPT}}" print --mode auto --machine "{{machine}}" --variant "{{variant}}")"; \
    TARGET="{{image_target}}"; \
    if [[ -z "$TARGET" ]]; then \
      TARGET="$(awk '$1=="target:"{print $2; exit}' "{{KAS_DIR}}/images/{{image}}.yml")"; \
    fi; \
    [[ -n "$TARGET" ]] || { echo "error: unable to resolve image target for image={{image}}" >&2; exit 1; }; \
    CONF_LINK="$DEPLOY_DIR/${TARGET}-{{machine}}.rootfs.qemuboot.conf"; \
    if [[ -f "$CONF_LINK" ]]; then \
      CONF="$CONF_LINK"; \
    else \
      CONF="$(ls -1t "$DEPLOY_DIR"/"${TARGET}"-"{{machine}}".rootfs-*.qemuboot.conf 2>/dev/null | head -n1 || true)"; \
    fi; \
    [[ -n "$CONF" ]] || { echo "error: qemuboot config not found under $DEPLOY_DIR" >&2; exit 1; }; \
    [[ -f "$POKY_INIT" ]] || { echo "error: missing $POKY_INIT. set POKY_INIT or fix YOCTO_ROOT." >&2; exit 1; }; \
    set +u; \
    source "$POKY_INIT" "$BUILD_DIR" > /dev/null; \
    set -u; \
    ARGS=("$CONF"); \
    if [[ "{{nographic}}" == "true" ]]; then ARGS+=("nographic"); fi; \
    echo "runqemu ${ARGS[*]}"; \
    runqemu "${ARGS[@]}"
