# balena-raspberrypi-abrp

Private **mirror** (not a GitHub fork — forks of public repos cannot be private) of
[balena-os/balena-raspberrypi](https://github.com/balena-os/balena-raspberrypi), carrying an
**additive layer + workflows** that build balenaOS **without balenaCloud** — publishable
as a public repo with **zero private-infra references** (verified: no instance hostnames,
no private registry, no internal IPs; history squashed to one commit on the upstream tag).

Full research & design: `open-balena/docs/hostapp-ota-research.md` (k8s repo), OpenSpec change
`add-hostapp-selfbuild`.

## Pipeline shape (GitHub + GHCR only)

```
build-supervisor.yml ──> ghcr.io/<owner>/aarch64-supervisor:<tag>   (arm64, native arm runner)
                                   │
build-os.yml ──> yocto-build-deploy.yml (patched copy, 4 jobs)
   │                 ├─ sstate: cross-run workflow artifacts on GH-hosted runners
   │                 │           (persistent /srv/yocto/shared when self-hosted)
   │                 └─ artifacts: <machine>-balena-image.docker, .img.zip, composition
   ├─ publish ─────> ghcr.io/<owner>/balenaos-hostapp/<machine>:<ver>
   └─ os-release ──> GitHub Releases tab (flashable balenaos-<ver>-<machine>.img.zip)
                                   │
                                   └─ k8s repo: scripts/import-hostapp-release.sh
                                      (pull GHCR image → push to YOUR registry2 →
                                       create+finalize hostApp release rows in YOUR api)
```

CI never talks to an openBalena instance: releases reach it only through the
operator-run import script (deliberate rollout gate).

## What is ours (everything else is untouched upstream @ pinned tags)

| Path | Purpose |
|---|---|
| `layers/meta-abrp/` | Yocto layer: `balena-supervisor.bbappend` pins `SUPERVISOR_IMAGE` to GHCR (`ghcr.io/volkermauel/aarch64-supervisor:v19.0.8`) — replaces the balenaCloud `supervisor_release` API query openBalena cannot answer; `docker-disk` entry.sh override pulls the same image at runtime; fatrw ssh→https; wget browser UA (crates.io 403); `conf/samples/` for barys `--templates-path`. |
| `.github/workflows/build-supervisor.yml` | Builds balena-supervisor from GitHub source (arm64) → `ghcr.io/<owner>/aarch64-supervisor:<tag>`. Runs on the `ubuntu-24.04-arm` runner — free for **public** repos; while the repo is private it needs larger-runner billing (or flip the repo public first). GHCR auth = `GITHUB_TOKEN`. **Run once before the first Yocto build** (the bbappend pins this image). |
| `.github/workflows/yocto-build-deploy.yml` | Patched copy of balena-yocto-scripts' reusable workflow (same commit the device repo pins). All patches marked `# abrp:` — see `scripts/patch-workflow.py` (the patcher itself; re-runnable, asserts on drift). Jobs: approved-commit, balena-lib, build, all_jobs (hostapp-deploy/ami-deploy/test/S3/AWS removed). |
| `.github/workflows/build-os.yml` | Caller: manual dispatch (version/machines) + nightly `detect` (upstream git tags − GHCR hostapp tags across ALL machines) → build → GHCR publish + flashable `.img` zips on the Releases tab. |
| `scripts/patch-workflow.py` | The workflow patcher (regenerate on upstream sync). |
| `scripts/sync-upstream.sh` | Fetch upstream tag, re-apply our additive tree, re-run the patcher. |

Upstream workflows (`raspberrypi*.yml`, `flowzone.yml`, `esr.yml`, …) are **removed**: they
fire on tag pushes and deploy to balena-cloud environments.

## Required repo configuration

- **While the repo is PRIVATE**, GitHub-hosted runners are billing-blocked — all
  small jobs carry a visibility-aware `runs-on` (`ubuntu-*` when public, the
  self-hosted runner otherwise) and self-heal at the public flip. detect runs
  every 6 h, builds OLDEST missing version first (floor `v7.4.0+rev5` — rev4 is
  already imported), one version per run.
- **No secrets, no environments needed.** Everything runs on `GITHUB_TOKEN`
  (packages read/write within the repo's own GHCR namespace). Optional repo vars:
  `DOCKERHUB_USER`/… see P8 in the patcher; a GitHub App (`BALENAOS_CI_APP_ID` +
  key) is optional.
- **Runner for the Yocto `build` job** (`build-runs-on` input to build-os):
  - self-hosted, labels `self-hosted,X64,yocto`, Docker, persistent
    `/srv/yocto/shared` (sstate/downloads) — **or**
  - GitHub-hosted **larger** runners (16+ core recommended; free-tier runners
    cannot fit Yocto: disk ≥90–140 GB + 6 h job cap). On GH-hosted runners the
    per-machine sstate dir is persisted as a **cross-run workflow artifact**
    (free for public repos; 30-day retention — a cold rebuild after a quiet
    period is expected) and build space is maximized via the LVM trick.
- **Fallback**: set the repo variable `YOCTO_PRIMARY_RUNS_ON` (JSON label array,
  e.g. `["linux-x64-16core"]`) to make GitHub-hosted runners primary; on any
  primary failure (incl. billing startup-failure) build-os retries the same
  machines on the self-hosted runner set after deleting the failed attempt's
  artifacts (`-sstate` is kept). Until the var is set, self-hosted is primary.
  `build-supervisor.yml` uses the same pattern natively: arm runner primary,
  self-hosted x64 + qemu binfmt fallback. GitHub has no built-in per-job
  runner-class retry — this is the standard two-call pattern.
- The GHCR packages (`aarch64-supervisor`, `balenaos-hostapp/*`) should be
  flipped to **public** once the repo is public (anonymous pulls then work
  everywhere, including the Yocto build and device fallbacks).

## Building

1. `build-supervisor.yml` (dispatch, tag = bbappend `SUPERVISOR_VERSION`)
2. `build-os.yml` (dispatch `version=v7.4.0+rev5` or wait for nightly detect)
3. Serve a release to devices: run the k8s repo's
   `scripts/import-hostapp-release.sh` against your openBalena instance
   (pulls the GHCR hostapp image, pushes it to your registry2, creates +
   finalizes the hostApp release; idempotent, same-semver rebuilds replace).

Artifacts per run: GHCR `balenaos-hostapp/<machine>:<ver>`, GitHub Release with
flashable `.img.zip` + SHA256SUMS, machine-suffixed workflow artifacts.

## Runner hardening log (self-hosted, Ubuntu 24.04, 2026-08-16)

Bisected silent `startup_failure` (zero check-runs) causes — all fixed in-repo:

1. **Caller permission ceiling**: called-workflow jobs cannot elevate above the caller's
   workflow-level grants. `build-os.yml` grants the union of all callee job-level perms
   (`pull-requests:write, contents:read, actions:read, id-token:write, packages:read`).
2. **Undeclared `with:` inputs** to a called workflow → startup_failure (not a dispatch 422).
3. **Action SHAs must be resolved from real tags** (two hallucinated SHAs broke job setup).
4. **Runner host prereqs**: `yq` (go-yq), `pipx` + `check-jsonschema` (PEP 668 blocks
   `pip install --user`), `sysctl kernel.apparmor_restrict_unprivileged_userns=0`
   (bitbake user namespaces vs AppArmor) — persisted in `/etc/sysctl.d/90-yocto-userns.conf`.
5. **Mirror tags**: `git push --tags` required — `git describe --abbrev=0` derives os_version.
6. **Layer collections**: `LAYERDEPENDS` uses collection names (`balena-common`), not layer
   dir names (`meta-balena-common`).
7. `auto.conf` was written by the removed S3-mirror step → Build now creates it (P16).
8. **GH-hosted ubuntu runners**: BitBake dies with "User namespaces are not usable
   by BitBake, possibly due to AppArmor" — set
   `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` before the
   build (P23; same fix as self-hosted, applied per-run).
