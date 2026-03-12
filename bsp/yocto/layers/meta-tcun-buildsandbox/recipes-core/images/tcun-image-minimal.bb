SUMMARY = "Minimal bootable image for QEMU bring-up"
LICENSE = "MIT"
PV = "${@d.getVar('VERSION') or '0.1.0-alpha'}"

inherit core-image

IMAGE_FEATURES += "ssh-server-openssh"

IMAGE_INSTALL = " \
    packagegroup-core-boot \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"
