# abrp: pin supervisor to the GHCR build.
# openBalena api has no /v6/supervisor_release resource, so the upstream API
# lookup is replaced by a static image reference. Bytes are built+pushed by
# .github/workflows/build-supervisor.yml (ghcr.io, public). arm64 only —
# matches our fleets (raspberrypi4-64, raspberrypi5).
SUPERVISOR_VERSION = "v19.0.8"
SUPERVISOR_IMAGE = "ghcr.io/volkermauel/aarch64-supervisor:v19.0.8"

api_fetch_supervisor_image() {
    echo "${SUPERVISOR_IMAGE}"
}

# abrp: supervisor composition (core-next + service-relay).
# Mirrors upstream balena-supervisor v19's docker-compose.yml but is deployed
# device-side by balena-supervisor-next.service instead of via target state,
# since openBalena has no supervisor fleets. The legacy supervisor container
# ("core") is deliberately NOT part of the composition: helios' takeover
# expects the single container started by start-balena-supervisor.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Helios version is global (meta-abrp layer.conf fallback, local.conf pin),
# following the SUPERVISOR_VERSION convention
#
# update-controlplane applies supervisor+helios pair releases from
# ghcr.io/volkermauel/controlplane-{supervisor,helios}: explicit pair
# tags for canary/rollback, the :stable channel via a daily timer.
# Pairing and labels: .github/workflows/build-controlplane.yml

SRC_URI:append = " \
    file://supervisor-compose.yml \
    file://balena-supervisor-next.service \
    file://supervisor-compose-env.sh \
    file://update-controlplane \
    file://update-controlplane.service \
    file://update-controlplane.timer \
    "

SYSTEMD_SERVICE:${PN} += "balena-supervisor-next.service"
SYSTEMD_SERVICE:${PN} += "update-controlplane.service update-controlplane.timer"

RDEPENDS:${PN} += "docker-compose"

do_install:append() {
    install -d ${D}${sysconfdir}/balena-supervisor
    # Render the build-time HELIOS_VERSION default into both the compose
    # file and the env generator (the runtime override in
    # /mnt/state/supervisor-compose.override takes precedence on device)
    sed -e "s,@HELIOS_VERSION@,${HELIOS_VERSION},g" \
        ${WORKDIR}/supervisor-compose.yml \
        > ${D}${sysconfdir}/balena-supervisor/supervisor-compose.yml
    chmod 0644 ${D}${sysconfdir}/balena-supervisor/supervisor-compose.yml

    install -m 0644 ${WORKDIR}/balena-supervisor-next.service \
        ${D}${systemd_unitdir}/system/balena-supervisor-next.service
    sed -e "s,@HELIOS_VERSION@,${HELIOS_VERSION},g" \
        ${WORKDIR}/supervisor-compose-env.sh \
        > ${D}${bindir}/supervisor-compose-env.sh
    chmod 0755 ${D}${bindir}/supervisor-compose-env.sh

    install -m 0755 ${WORKDIR}/update-controlplane \
        ${D}${bindir}/update-controlplane
    install -m 0644 ${WORKDIR}/update-controlplane.service \
        ${D}${systemd_unitdir}/system/update-controlplane.service
    install -m 0644 ${WORKDIR}/update-controlplane.timer \
        ${D}${systemd_unitdir}/system/update-controlplane.timer
}
