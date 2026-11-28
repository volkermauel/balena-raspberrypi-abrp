# abrp: entry.sh override (supervisor pulled from our registry2, not the
# balena_os/<fleet>-supervisor API lookup that openBalena cannot answer)
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# abrp: render the helios image version into entry.sh. The docker build
# that COPYs entry.sh runs in do_compile (do_patch/do_configure are noexec
# in this recipe, and do_install runs after do_compile). Recopy the pristine
# file first so a stale rendered entry.sh in a reused WORKDIR can't mask
# HELIOS_VERSION changes.
do_compile:prepend() {
    install -m 0755 ${THISDIR}/files/entry.sh ${WORKDIR}/entry.sh
    sed -i "s,@HELIOS_VERSION@,${HELIOS_VERSION},g" ${WORKDIR}/entry.sh
}
