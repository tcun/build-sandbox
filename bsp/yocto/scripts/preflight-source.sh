#!/usr/bin/env bash
set -euo pipefail

variant="${1:-}"
if [[ -z "${variant}" ]]; then
    echo "usage: preflight-source.sh <variant>" >&2
    exit 2
fi

echo "=== shell env ==="
env | grep -E '^(TEMPLATE_VERSION|TEMPLATE_BUILD_VERSION|SOURCE_REV|SMOKE_CORE_EXTERNALSRC|BB_ENV_PASSTHROUGH_ADDITIONS)=' || true

env_dump="$(mktemp)"
trap 'rm -f "${env_dump}"' EXIT

bitbake -e smoke-core > "${env_dump}"

echo "=== bitbake env (smoke-core) ==="
grep -E '^(TEMPLATE_VERSION|TEMPLATE_BUILD_VERSION|BUILD_FLAVOR|SOURCE_MODE|SRC_URI|SRCREV|SOURCE_REV|EXTERNALSRC|PSEUDO_DISABLED)=' "${env_dump}" || true

if grep -Eq '^PSEUDO_DISABLED="1"' "${env_dump}"; then
    echo "error: PSEUDO_DISABLED=1 detected for smoke-core; fakeroot packaging will fail" >&2
    exit 1
fi

if ! grep -Eq '^do_package\[fakeroot\]="1"' "${env_dump}"; then
    echo "error: smoke-core do_package is not marked fakeroot=1" >&2
    exit 1
fi

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
