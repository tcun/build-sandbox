#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  env-contract.sh print [--mode <auto|local|ci>] [--machine <name>] [--variant <name>] [--artifact-root <dir>]
  env-contract.sh check [--mode <auto|local|ci>] [--machine <name>] [--variant <name>] [--artifact-root <dir>] [--require <csv>]

Contract:
  - YOCTO_ROOT: required in CI mode, local default <repo>/build/yocto
  - ARTIFACT_ROOT: env/default /srv/yocto-artifacts
  - POKY_INIT: env/default ${YOCTO_ROOT}/sources/poky/oe-init-build-env
  - BUILD_DIR/DEPLOY_DIR: always derived from YOCTO_ROOT + machine + variant
USAGE
}

resolve_root_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/../../.." && pwd
}

normalize_mode() {
  local mode="$1"
  if [[ "$mode" == "auto" ]]; then
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      echo "ci"
    else
      echo "local"
    fi
  else
    echo "$mode"
  fi
}

run_print() {
  local mode="$1" machine="$2" variant="$3" artifact_root_arg="$4"
  local root_dir ci_mode yocto_root_value artifact_root_value poky_init_value build_dir deploy_dir

  root_dir="$(resolve_root_dir)"
  ci_mode="$(normalize_mode "$mode")"

  if [[ "$ci_mode" != "local" && "$ci_mode" != "ci" ]]; then
    echo "error: mode must be auto|local|ci" >&2
    exit 2
  fi

  yocto_root_value="${YOCTO_ROOT:-}"
  if [[ -z "$yocto_root_value" ]]; then
    if [[ "$ci_mode" == "ci" ]]; then
      echo "error: YOCTO_ROOT is required in CI mode" >&2
      exit 1
    fi
    yocto_root_value="$root_dir/build/yocto"
  fi

  if [[ "$yocto_root_value" != /* ]]; then
    echo "error: YOCTO_ROOT must be an absolute path (got '$yocto_root_value')" >&2
    exit 1
  fi

  if [[ -n "$artifact_root_arg" ]]; then
    artifact_root_value="$artifact_root_arg"
  else
    artifact_root_value="${ARTIFACT_ROOT:-/srv/yocto-artifacts}"
  fi

  if [[ "$artifact_root_value" != /* ]]; then
    echo "error: ARTIFACT_ROOT must be an absolute path (got '$artifact_root_value')" >&2
    exit 1
  fi

  poky_init_value="${POKY_INIT:-$yocto_root_value/sources/poky/oe-init-build-env}"
  if [[ "$poky_init_value" != /* ]]; then
    echo "error: POKY_INIT must be an absolute path (got '$poky_init_value')" >&2
    exit 1
  fi

  build_dir="$yocto_root_value/build/${machine}-${variant}"
  deploy_dir="$build_dir/tmp/deploy/images/$machine"

  echo "ROOT_DIR=$root_dir"
  echo "CONTRACT_MODE=$ci_mode"
  echo "YOCTO_ROOT=$yocto_root_value"
  echo "BUILD_DIR=$build_dir"
  echo "DEPLOY_DIR=$deploy_dir"
  echo "POKY_INIT=$poky_init_value"
  echo "ARTIFACT_ROOT=$artifact_root_value"
}

check_path_exists() {
  local kind="$1" path="$2"
  case "$kind" in
    yocto_root|build|deploy|artifact_root)
      [[ -d "$path" ]] || { echo "error: missing $kind dir: $path" >&2; return 1; }
      ;;
    poky)
      [[ -f "$path" ]] || { echo "error: missing poky init: $path" >&2; return 1; }
      ;;
    *)
      echo "error: unknown required path kind '$kind'" >&2
      return 1
      ;;
  esac
}

run_check() {
  local mode="$1" machine="$2" variant="$3" artifact_root_arg="$4" require_csv="$5"
  local outputs

  outputs="$(run_print "$mode" "$machine" "$variant" "$artifact_root_arg")"
  eval "$outputs"

  if [[ -n "$require_csv" ]]; then
    IFS=',' read -r -a required_items <<< "$require_csv"
    for item in "${required_items[@]}"; do
      item="${item//[[:space:]]/}"
      [[ -n "$item" ]] || continue
      case "$item" in
        yocto_root) check_path_exists yocto_root "$YOCTO_ROOT" ;;
        build) check_path_exists build "$BUILD_DIR" ;;
        deploy) check_path_exists deploy "$DEPLOY_DIR" ;;
        poky) check_path_exists poky "$POKY_INIT" ;;
        artifact_root) check_path_exists artifact_root "$ARTIFACT_ROOT" ;;
        *) echo "error: unsupported require item '$item'" >&2; exit 1 ;;
      esac
    done
  fi

  echo "ok: env contract check passed"
  echo "$outputs"
}

main() {
  local cmd="${1:-}"
  local mode="auto"
  local machine="qemux86-64"
  local variant="dev"
  local artifact_root_arg=""
  local require_csv=""

  [[ -n "$cmd" ]] || { usage; exit 2; }
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode="$2"; shift 2 ;;
      --machine) machine="$2"; shift 2 ;;
      --variant) variant="$2"; shift 2 ;;
      --artifact-root) artifact_root_arg="$2"; shift 2 ;;
      --require) require_csv="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "error: unknown argument '$1'" >&2; usage; exit 2 ;;
    esac
  done

  case "$cmd" in
    print)
      run_print "$mode" "$machine" "$variant" "$artifact_root_arg"
      ;;
    check)
      run_check "$mode" "$machine" "$variant" "$artifact_root_arg" "$require_csv"
      ;;
    *)
      echo "error: unknown command '$cmd'" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
