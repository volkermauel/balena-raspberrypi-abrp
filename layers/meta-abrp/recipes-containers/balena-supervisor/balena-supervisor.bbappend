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
