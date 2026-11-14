SUMMARY = "Standalone Docker Compose binary"
DESCRIPTION = "Prebuilt docker-compose standalone binary used by \
balena-supervisor-next.service to run the supervisor composition \
(core-next/service-relay) on the device."
HOMEPAGE = "https://github.com/docker/compose"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

# Only the aarch64 release artifact is fetched; this matches the device
# types built from this layer (raspberrypi4-64, raspberrypi5)
COMPATIBLE_HOST = "(aarch64).*-linux"

SRC_URI = "https://github.com/docker/compose/releases/download/v${PV}/docker-compose-linux-aarch64;name=main"
SRC_URI[main.sha256sum] = "ff42489f5a9b879d5d117c5ffea6defc27390b3286da8ad52cbc9c6ab5df590e"

PV = "5.5.0"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/docker-compose-linux-aarch64 ${D}${bindir}/docker-compose
}

# Release binaries are already stripped
INSANE_SKIP:${PN} += "already-stripped"
