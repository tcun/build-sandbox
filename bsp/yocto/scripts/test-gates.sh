#!/usr/bin/env bash
set -euo pipefail

MACHINE="${1:-qemux86-64}"
VARIANT="${2:-test}"
IMAGE="${3:-minimal}"
RUN_SIMULATOR="${RUN_SIMULATOR:-true}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
KAS_DIR="$ROOT_DIR/bsp/yocto/kas"
YOCTO_ROOT_VALUE="${YOCTO_ROOT:-$ROOT_DIR/build/yocto}"
BUILD_DIR="$YOCTO_ROOT_VALUE/build/${MACHINE}-${VARIANT}"
DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/$MACHINE"
POKY_INIT="$YOCTO_ROOT_VALUE/sources/poky/oe-init-build-env"

if [[ ! -d "$DEPLOY_DIR" ]]; then
  CANDIDATE_YOCTO_ROOTS=(
    "$YOCTO_ROOT_VALUE"
    "$ROOT_DIR/build/yocto"
  )
  if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    CANDIDATE_YOCTO_ROOTS+=("$(dirname "$GITHUB_WORKSPACE")/yocto-state")
  fi
  for candidate_root in "${CANDIDATE_YOCTO_ROOTS[@]}"; do
    candidate_deploy="$candidate_root/build/${MACHINE}-${VARIANT}/tmp/deploy/images/$MACHINE"
    if [[ -d "$candidate_deploy" ]]; then
      YOCTO_ROOT_VALUE="$candidate_root"
      BUILD_DIR="$YOCTO_ROOT_VALUE/build/${MACHINE}-${VARIANT}"
      DEPLOY_DIR="$candidate_deploy"
      POKY_INIT="$YOCTO_ROOT_VALUE/sources/poky/oe-init-build-env"
      break
    fi
  done
fi

[[ -d "$DEPLOY_DIR" ]] || { echo "error: missing deploy dir: $DEPLOY_DIR" >&2; exit 1; }

if [[ ! -f "$POKY_INIT" ]]; then
  CANDIDATE_POKY_INITS=(
    "$YOCTO_ROOT_VALUE/sources/poky/oe-init-build-env"
    "$ROOT_DIR/build/yocto/sources/poky/oe-init-build-env"
  )
  if [[ -n "${YOCTO_ROOT:-}" ]]; then
    CANDIDATE_POKY_INITS+=("${YOCTO_ROOT}/sources/poky/oe-init-build-env")
  fi
  if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
    CANDIDATE_POKY_INITS+=("$(dirname "$GITHUB_WORKSPACE")/yocto-state/sources/poky/oe-init-build-env")
  fi
  for candidate_poky_init in "${CANDIDATE_POKY_INITS[@]}"; do
    if [[ -f "$candidate_poky_init" ]]; then
      POKY_INIT="$candidate_poky_init"
      break
    fi
  done
fi

CONF_FILE="$(ls -1 "$DEPLOY_DIR"/*.qemuboot.conf 2>/dev/null | head -n1 || true)"
[[ -n "$CONF_FILE" ]] || { echo "error: missing qemuboot.conf (bootable image not found)" >&2; exit 1; }

ROOTFS_FILE="$(ls -1 "$DEPLOY_DIR"/*.rootfs.* 2>/dev/null | head -n1 || true)"
[[ -n "$ROOTFS_FILE" ]] || { echo "error: missing rootfs artifact" >&2; exit 1; }

MANIFEST_FILE="$(ls -1 "$DEPLOY_DIR"/*.manifest 2>/dev/null | head -n1 || true)"
[[ -n "$MANIFEST_FILE" ]] || { echo "error: missing image manifest" >&2; exit 1; }

grep -Eq '^smoke-core($|[[:space:]])' "$MANIFEST_FILE" || {
  echo "error: smoke-core package missing from image manifest" >&2
  exit 1
}

grep -Eiq 'openssh|ssh' "$MANIFEST_FILE" || {
  echo "error: ssh package missing from image manifest" >&2
  exit 1
}

if [[ "$RUN_SIMULATOR" == "true" ]]; then
  [[ -f "$POKY_INIT" ]] || { echo "error: missing $POKY_INIT" >&2; exit 1; }

  IMAGE_TARGET="$(awk '$1=="target:"{print $2; exit}' "$KAS_DIR/images/${IMAGE}.yml" 2>/dev/null || true)"
  if [[ -z "$IMAGE_TARGET" ]]; then
    IMAGE_TARGET="template-image-minimal"
  fi

  QEMU_CONF_LINK="$DEPLOY_DIR/${IMAGE_TARGET}-${MACHINE}.rootfs.qemuboot.conf"
  if [[ -f "$QEMU_CONF_LINK" ]]; then
    QEMU_CONF="$QEMU_CONF_LINK"
  else
    QEMU_CONF="$CONF_FILE"
  fi

  QEMU_LOG="$(mktemp)"
  cleanup() {
    rm -f "$QEMU_LOG"
  }
  trap cleanup EXIT

  set +e
  (
    set +u
    source "$POKY_INIT" "$BUILD_DIR" >/dev/null
    set -u
    timeout 180s runqemu "$QEMU_CONF" nographic >"$QEMU_LOG" 2>&1
  )
  RC=$?
  set -e

  if [[ $RC -ne 0 && $RC -ne 124 ]]; then
    echo "error: runqemu failed with exit code $RC" >&2
    tail -n 120 "$QEMU_LOG" >&2 || true
    exit $RC
  fi

  grep -Eiq 'login:|Starting OpenBSD Secure Shell server|Reached target' "$QEMU_LOG" || {
    echo "error: simulator boot log did not reach expected readiness markers" >&2
    tail -n 120 "$QEMU_LOG" >&2 || true
    exit 1
  }
fi

echo "Test profile gates passed for ${MACHINE}/${VARIANT}."
