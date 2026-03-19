SUMMARY = "Template smoke application for build-flavor verification"
LICENSE = "CLOSED"

inherit cargo_bin

PV = "${@d.getVar('TEMPLATE_VERSION') or '0.1.0-alpha'}"

# Keep packaging under fakeroot even if environment leakage occurs in CI runners.
# Without fakeroot, do_package will attempt real lchown() calls and fail in
# rootless/containerized executions.
PSEUDO_DISABLED = "0"
do_package[fakeroot] = "1"

# Immutable source inputs for reproducible builds:
# - SOURCE_BRANCH chooses the git stream
# - SOURCE_REV pins an exact commit (set by CI release flow)
SOURCE_BRANCH ?= "main"
SOURCE_REV ?= ""

SRC_URI = "git://github.com/tcun/build-sandbox.git;protocol=ssh;user=git;branch=${SOURCE_BRANCH}"
SRCREV = "${@d.getVar('SOURCE_REV') if d.getVar('SOURCE_REV') else d.getVar('AUTOREV')}"
S = "${WORKDIR}/git"

# Default flavor; distro config should override this (dev/test/release).
BUILD_FLAVOR ?= "dev"
SOURCE_MODE ?= "canonical"

python () {
    flavor = (d.getVar("BUILD_FLAVOR") or "").strip()
    source_rev = (d.getVar("SOURCE_REV") or "").strip()
    if flavor in ("test", "release") and not source_rev:
        bb.fatal(
            "SOURCE_REV must be set for smoke-core when BUILD_FLAVOR is '%s'" % flavor
        )
}

# Build the workspace and select smoke-core binary.
CARGO_MANIFEST_PATH = "${S}/apps/Cargo.toml"
CARGO_BUILD_FLAGS:append = " -p smoke-core"
do_compile[network] = "1"

do_install:append() {
    install -d ${D}${sysconfdir}
    printf "%s\n" "${BUILD_FLAVOR}" > ${D}${sysconfdir}/build-flavor
}
