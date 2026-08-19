# Tasks: add-supervisor-composition

## 1. OpenSpec

- [x] Scaffold openspec/ (init, no AI tool config)
- [x] Write proposal.md, design.md, tasks.md, spec delta
- [x] Validate change: `openspec validate add-supervisor-composition`

## 2. docker-compose recipe

- [x] `layers/meta-abrp/recipes-devtools/docker-compose/docker-compose.bb` — v5.5.0 aarch64 binary, sha256-pinned, `/usr/bin/docker-compose`

## 3. Composition deployment

- [x] `files/supervisor-compose.yml` — core-next + service-relay, env interpolated from `/run/supervisor-compose.env`, `supervisor0` external network
- [x] `files/supervisor-compose-env.sh` — wait for supervisor, extract API key, ensure `supervisor0`, write env file
- [x] `files/balena-supervisor-next.service` — oneshot unit, runs after balena-supervisor.service
- [x] `balena-supervisor.bbappend` — FILESEXTRAPATHS, SRC_URI, SYSTEMD_SERVICE, RDEPENDS, do_install:append with @HELIOS_VERSION@ rendering
- [x] Global `HELIOS_VERSION` (layer.conf `?=` fallback + local.conf.sample pin) following the SUPERVISOR_VERSION convention

## 4. Preload

- [x] `docker-disk/files/entry.sh` — pull `ghcr.io/balena-io/helios:@HELIOS_VERSION@` (rendered by docker-disk.bbappend `do_compile:prepend`; first CI attempt failed because the sed ran in `do_install`, after the docker build — fixed)
- [x] Verified `ghcr.io/balena-io/helios:0.25.28` anonymously pullable (manifest 200, digest sha256:5bd00cbefe75…) — no self-build required

## 5. Verification

- [x] `sh -n` on all shipped shell scripts (raw and @HELIOS_VERSION@-rendered)
- [x] Render supervisor-compose.yml and validate with the exact compose v5.5.0 binary (`docker-compose config`)
- [x] Render entry.sh placeholder and verify resulting image ref
- [x] GitHub CI (run 32258564461: both machines green after 3 fix iterations — see design.md) (`build-os.yml` → `yocto-build-deploy.yml`, machines raspberrypi4-64/raspberrypi5, `-t layers/meta-abrp/conf/samples`): bitbake parse + full image build — covered by the existing pipeline once pushed
- [ ] Device smoke test: unit active, both containers running, supervisor reports via proxy, takeover keys present in DB
