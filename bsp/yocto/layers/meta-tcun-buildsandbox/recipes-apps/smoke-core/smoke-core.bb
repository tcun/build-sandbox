SUMMARY = "Template smoke application for build-flavor verification"
LICENSE = "CLOSED"

inherit cargo

PV = "${@d.getVar('VERSION') or '0.1.0-alpha'}"

# Immutable source inputs for reproducible builds:
# - SOURCE_REPO / SOURCE_BRANCH choose the git stream
# - SOURCE_REV pins an exact commit (set by CI release flow)
SOURCE_REPO ?= "github.com/tcun/build-sandbox.git"
SOURCE_BRANCH ?= "main"
SOURCE_REV ?= ""

SRC_URI = "git://${SOURCE_REPO};protocol=https;branch=${SOURCE_BRANCH}"
SRCREV = "${@d.getVar('SOURCE_REV') if d.getVar('SOURCE_REV') else d.getVar('AUTOREV')}"
S = "${WORKDIR}/git"

# Default flavor; distro config should override this (dev/test/release).
TCUN_BUILD_FLAVOR ?= "dev"

# Build the workspace and select smoke-core binary.
CARGO_MANIFEST_PATH = "${S}/apps/Cargo.toml"
CARGO_BUILD_FLAGS:append = " -p smoke-core"

do_install:append() {
    install -d ${D}${sysconfdir}
    printf "%s\n" "${TCUN_BUILD_FLAVOR}" > ${D}${sysconfdir}/tcun-build-flavor
}
