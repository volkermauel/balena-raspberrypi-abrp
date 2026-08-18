# abrp: entry.sh override (supervisor pulled from our registry2, not the
# balena_os/<fleet>-supervisor API lookup that openBalena cannot answer)
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
