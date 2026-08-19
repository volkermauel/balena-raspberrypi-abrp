# abrp: entry.sh override (supervisor pulled from our registry2, not the
# balena_os/<fleet>-supervisor API lookup that openBalena cannot answer)
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# abrp: render the helios image version into entry.sh. do_configure is
# noexec in this recipe, so hook do_install instead (runs before the
# docker build that COPYs entry.sh).
do_install:prepend() {
    sed -i "s,@HELIOS_VERSION@,${HELIOS_VERSION},g" ${WORKDIR}/entry.sh
}
