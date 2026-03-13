#!/usr/bin/env bash
set -euo pipefail

variant="${1:-}"
if [[ -z "${variant}" ]]; then
    echo "usage: preflight-source.sh <variant>" >&2
    exit 2
fi

echo "=== shell env ==="
env | grep -E '^(SOURCE_REV|SMOKE_CORE_EXTERNALSRC|BB_ENV_PASSTHROUGH_ADDITIONS)=' || true

env_dump="$(mktemp)"
trap 'rm -f "${env_dump}"' EXIT

bitbake -e smoke-core > "${env_dump}"

echo "=== bitbake env (smoke-core) ==="
grep -E '^(TCUN_BUILD_FLAVOR|TCUN_SOURCE_MODE|SRC_URI|SRCREV|SOURCE_REV|EXTERNALSRC)=' "${env_dump}" || true

if [[ "${variant}" == "test" || "${variant}" == "release" ]]; then
    if grep -Eq '^SRC_URI="[^"]*protocol=file' "${env_dump}"; then
        echo "error: canonical variants must not resolve smoke-core SRC_URI to protocol=file" >&2
        exit 1
    fi

    externalsrc_value="$(sed -n 's/^EXTERNALSRC="\(.*\)"/\1/p' "${env_dump}" | head -n 1)"
    if [[ -n "${externalsrc_value}" ]]; then
        echo "error: canonical variants must not set EXTERNALSRC (found: ${externalsrc_value})" >&2
        exit 1
    fi
fi
