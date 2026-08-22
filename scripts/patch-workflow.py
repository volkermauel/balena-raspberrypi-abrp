#!/usr/bin/env python3
"""Patch yocto-build-deploy.yml for the public abrp self-build pipeline.

Zero references to private infra (openBalena instance hostnames/registries):
- supervisor container comes from ghcr.io (build-supervisor.yml publishes it)
- hostapp-deploy/ami-deploy jobs are removed; releases reach openBalena via
  the k8s-repo import script (scripts/import-hostapp-release.sh)
- sstate persists as cross-run workflow artifacts on GitHub-hosted runners
  (free for public repos) and on the runner-local shared dir when self-hosted

Every replacement is exact-match with count assertions — fails loudly on drift.
"""
import sys
from pathlib import Path

p = Path('.github/workflows/yocto-build-deploy.yml')
t = p.read_text()
orig = t

def rep(old, new, count=1):
    global t
    found = t.count(old)
    assert found == count, f"expected {count} occurrence(s), found {found}:\n---\n{old[:300]}\n---"
    t = t.replace(old, new)

# ── P1: soften GitHub-App decode ────────────────────────────────────────────
rep('''          if [[ -z "$SECRET_VALUE" ]]; then
            echo "::error::BALENAOS_CI_APP_PRIVATE_KEY secret is not set"
            exit 1
          fi''',
    '''          if [[ -z "$SECRET_VALUE" ]]; then
            echo "::warning::BALENAOS_CI_APP_PRIVATE_KEY not set - GitHub App auth disabled (abrp)"
            echo "private-key=" >> "$GITHUB_OUTPUT"
            exit 0
          fi''', count=3)

# ── P2: gate the create-github-app-token steps on the App being configured ──
rep('''        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
        id: app-token
''',
    '''        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
        id: app-token
        if: ${{ vars.BALENAOS_CI_APP_ID != '' }}
''', count=3)
rep('''        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
        id: app-token-balena-io
''',
    '''        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
        id: app-token-balena-io
        if: ${{ vars.BALENAOS_CI_APP_ID != '' }}
''', count=3)

# ── P3: is_private → false (openBalena DeviceType has no is_private) ────────
old_script = t[t.index('            const result = await fetch(`https://api.${process.env.API_ENV}/${process.env.TRANSLATION}/device_type?'):t.index('            return data.d[0].is_private') + len('            return data.d[0].is_private\n')]
rep(old_script,
    '''            // abrp: openBalena api has no is_private on device_type - hardcode public
            return false
''')

# ── P4: drop source-mirror-setup job + needs + MIRRORS step ─────────────────
start = t.index('  # This job is used to separate the AWS environment')
end = t.index('  build:')
t = t[:start] + t[end:]
rep('''    needs:
      - approved-commit
      - balena-lib
      - source-mirror-setup
''',
    '''    needs:
      - approved-commit
      - balena-lib
''')
s = t.index('      - name: Add S3 shared-downloads to MIRRORS')
e = t.index('      - name: Install openssh-client package')
t = t[:s] + t[e:]

# ── P5: drop MinIO/tespkg sstate machinery + awscli + AWS creds + S3 sync ──
# (sstate now persists via P21 cross-run artifacts on GH-hosted runners)
s = t.index('      # Use local S3 cache on self-hosted runners.')
e = t.index('      - name: Login to Docker Hub')
t = t[:s] + t[e:]

# ── P6: shared build dir — persistent path on self-hosted, workspace else ───
rep('          SHARED_BUILD_DIR: ${{ github.workspace }}/shared',
    "          SHARED_BUILD_DIR: ${{ contains(join(fromJSON(inputs.build-runs-on), ','), 'self-hosted') && '/srv/yocto/shared' || format('{0}/shared', github.workspace) }}  # abrp: /srv on self-hosted, workspace (artifact-sstate) otherwise", count=2)

# ── P7: ssh-agent guard (no YOCTO_SSH_PRIVATE_KEY_B64 secret) ───────────────
rep('''          >&2 eval "$(ssh-agent)"
          echo "${{ secrets.YOCTO_SSH_PRIVATE_KEY_B64 }}" | base64 -d | ssh-add - >&2''',
    '''          >&2 eval "$(ssh-agent)"
          # abrp: SSH key optional (no private submodules)
          if [ -n "${YOCTO_SSH_PRIVATE_KEY_B64}" ]; then
            echo "${YOCTO_SSH_PRIVATE_KEY_B64}" | base64 -d | ssh-add - >&2
          fi''')

# ── P8: Docker Hub login only when secrets exist ────────────────────────────
rep('''      - name: Login to Docker Hub
        uses: docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9 # v3.7.0
        with:''',
    '''      - name: Login to Docker Hub
        uses: docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9 # v3.7.0
        if: ${{ vars.DOCKERHUB_USER != '' }}
        with:''')

# ── P9: CLI pin v25.2.3 (verified against openBalena api v49) ───────────────
rep('          BALENA_CLI_VERSION: v24.0.3', '          BALENA_CLI_VERSION: v25.2.3', count=2)

# ── P10: skip release-asset staging/upload (openBalena webresources) ────────
rep('''      - name: Stage extension release assets
        run: |''',
    '''      - name: Stage extension release assets
        if: false # abrp: release webresources not served by openBalena api
        run: |''')
rep('''      - name: Upload release assets
        uses: balena-io/upload-balena-release-asset@52cceb8fc25e0bfdb433b92567a434d1a5baecda # v0.1.6
        with:''',
    '''      - name: Upload release assets
        uses: balena-io/upload-balena-release-asset@52cceb8fc25e0bfdb433b92567a434d1a5baecda # v0.1.6
        if: false # abrp: release webresources not served by openBalena api
        with:''')

# ── P11: drop s3-deploy job + needs references ──────────────────────────────
s = t.index('  ##############################\n  # S3 Deploy')
e = t.index('  ##############################\n  # AMI Deploy')
t = t[:s] + t[e:]
rep('''      - build
      - balena-lib
      - s3-deploy
''',
    '''      - build
      - balena-lib
''')
rep('''      - build
      - s3-deploy
      - ami-deploy
''',
    '''      - build
      - ami-deploy
''')

# ── P13: drop leviathan test job (local action path breaks called-workflow ──
# validation: ./layers/meta-balena/tests/leviathan does not exist in our tree;
# job was always skipped for us anyway — test_matrix empty)
start = t.index('\n  test:\n')
end = t.index('\n  all_jobs:')
t = t[:start] + t[end:]
rep("""      - ami-deploy
      - hostapp-deploy
      - test
""",
    """      - ami-deploy
      - hostapp-deploy
""")

# ── P14: build job environment: '' is an invalid env name at runtime ────────
# (startup_failure with zero check-runs); we never sign → drop the line
rep("    environment: ${{ inputs.signing-environment }}\n",
    "    # abrp: signing environment removed — empty-string environment: is a startup_failure\n")

# ── P16: auto.conf was created by the removed S3 MIRRORS step; create it ─────
rep("""          mkdir -p "${SHARED_BUILD_DIR}"

          cat "${AUTO_CONF_FILE}"
""",
    """          mkdir -p "${SHARED_BUILD_DIR}"

          # abrp: upstream created auto.conf in the (removed) S3 MIRRORS step;
          # create it empty here so the read below works
          mkdir -p "$(dirname "${AUTO_CONF_FILE}")"
          touch "${AUTO_CONF_FILE}"
          cat "${AUTO_CONF_FILE}"
""")

# ── P17: skip Prepare deflate files (balena/balena-img is a private Docker ──
# Hub helper; deflate files only feed the balenaCloud img-maker we don't use)
rep("""      - name: Prepare deflate files
        if: matrix.image_class == 'hostapp'
        env:
          HELPER_IMAGE: balena/balena-img:6.20.26""",
    """      - name: Prepare deflate files
        # abrp: balena/balena-img is a PRIVATE Docker Hub image (upstream CI uses
        # DOCKERHUB_* secrets); deflate files only feed the balenaCloud img-maker
        # (os download) which we do not use — hostapp deploy needs balena-image.docker only
        if: matrix.image_class == 'hostapp' && false""")

# ── P20: remove hostapp-deploy + ami-deploy (public pipeline: releases reach
# openBalena via the k8s-repo import script, not from CI) ────────────────────
s = t.index('  ##############################\n  # hostapp Deploy')
e = t.index('  ##############################\n  # Leviathan Test')
t = t[:s] + t[e:]
rep('''      - approved-commit
      - balena-lib
      - build
      - ami-deploy
      - hostapp-deploy
''',
    '''      - approved-commit
      - balena-lib
      - build
''')
rep('            deploy-environment: ${{ inputs.deploy-environment }}\n', '')
rep('''      deploy-environment:
        description: The balena environment to use for hostApp deployment - includes the related vars and secrets
        required: false
        type: string
        default: balena-cloud.com
''', '')
rep("  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}-${{ inputs.machine }}-${{ inputs.deploy-environment }}",
    "  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}-${{ inputs.machine }}")
rep("    environment: ${{ inputs.deploy-environment || 'balena-cloud.com' }}\n", '')
rep('''      # For use when we need to force deploy a release, for example after manual testing (negates finalize-on-push-if-tests-pass)
      force-finalize:
        description: Force deploy a finalized release
        required: false
        type: boolean
        default: false
''', '')
rep("      should_finalize: ${{ steps.merge-test-result.outputs.finalize == 'true' || inputs.force-finalize }}",
    "      should_finalize: false  # abrp: hostapp-deploy removed — releases reach openBalena via k8s scripts/import-hostapp-release.sh")

# ── P18: machine-suffix artifact names (we fan out multiple machines;
# upstream builds one machine per run and uses fixed names -> collisions).
# Runs AFTER P20: hostapp-deploy/s3-deploy also upload same-named artifacts;
# deleting those jobs first collapses each pattern to the build job's one.
rep('          name: hostapp-composition\n',
    '          name: ${{ env.MACHINE }}-hostapp-composition  # abrp: machine-suffixed (multi-machine fanout)\n')
rep('          name: hostapp-artifacts\n',
    '          name: ${{ env.MACHINE }}-hostapp-artifacts  # abrp\n')
rep('          name: kernel-module-headers\n',
    '          name: ${{ env.MACHINE }}-kernel-module-headers  # abrp\n')
rep('          name: balena-image.docker\n',
    '          name: ${{ env.MACHINE }}-balena-image.docker  # abrp\n')
rep('          name: balena.img.zip\n',
    '          name: ${{ env.MACHINE }}-balena.img.zip  # abrp\n')
rep('          name: extension-${{ matrix.service_name }}\n',
    '          name: ${{ env.MACHINE }}-extension-${{ matrix.service_name }}  # abrp\n')

# ── P21: cross-run sstate via workflow artifacts (GitHub-hosted runners) ────
# Self-hosted runners keep their persistent /srv dir and skip both steps.
# NOTE: bare expression, no ${{ }} wrapper — wrapped + bare text = literal concat = always-true
SSTATE_IF = "!contains(join(fromJSON(inputs.build-runs-on), ','), 'self-hosted')"

_restore = '''      - name: Restore sstate cache (cross-run artifact)
        # abrp: no persistent runner dir on GitHub-hosted runners — keep the
        # per-machine sstate dir as a workflow artifact (free for public repos)
        # and restore the latest non-expired one before building. Cold build on
        # the first run / after retention expiry is expected and fine.
        # (quoted: a bare leading ! parses as a YAML tag)
        if: "@@IF@@"
        env:
          GH_TOKEN: ${{ github.token }}
          SHARED_BUILD_DIR: ${{ github.workspace }}/shared
        run: |
          set -euo pipefail
          art_id=$(gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts?name=${MACHINE}-sstate&per_page=1" --jq '.artifacts[0] | select(.expired == false) | .id')
          if [ -z "${art_id}" ]; then
            echo "no ${MACHINE}-sstate artifact available — cold build"
            exit 0
          fi
          echo "restoring sstate artifact id=${art_id}"
          mkdir -p "${SHARED_BUILD_DIR}/${MACHINE}"
          curl --silent --show-error --location \\
            -H "Authorization: token ${GH_TOKEN}" \\
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/artifacts/${art_id}/zip" \\
            -o /tmp/sstate.zip
          # abrp: stream zip->tar->extract so peak disk stays at zip + extracted
          # (a first attempt kept zip + inner tar + extracted ~= 15G on the
          # ~20G root disk and killed the runner agent mid-restore).
          unzip -p /tmp/sstate.zip sstate.tar | tar -xf - -C "${SHARED_BUILD_DIR}/${MACHINE}"
          rm -f /tmp/sstate.zip
          du -sh "${SHARED_BUILD_DIR}/${MACHINE}/sstate" || true

      - name: Build
        id: build
        env:'''
_userns = '''      - name: Allow BitBake user namespaces (Ubuntu 24.04 AppArmor)
        # abrp: GH-hosted ubuntu runners ship
        # kernel.apparmor_restrict_unprivileged_userns=1 - BitBake/pseudo
        # cannot create user namespaces ("User namespaces are not usable by
        # BitBake, possibly due to AppArmor"). Same sysctl fix as our
        # self-hosted runner (persisted there via /etc/sysctl.d), per-run here.
        if: "@@IF@@"
        run: sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0

'''
rep('''      - name: Build
        id: build
        env:''',
    _userns.replace('@@IF@@', SSTATE_IF) + _restore.replace('@@IF@@', SSTATE_IF))

_save = '''      - name: Save sstate cache (cross-run artifact)
        # abrp: only the hostapp matrix leg saves — all legs share one artifact
        # name, parallel extension legs would race ("artifact name conflict").
        if: "@@IF@@ && matrix.image_class == 'hostapp'"
        env:
          SHARED_BUILD_DIR: ${{ github.workspace }}/shared
        run: |
          set -euo pipefail
          tar -cf /tmp/sstate.tar -C "${SHARED_BUILD_DIR}/${MACHINE}" sstate

      - name: Upload sstate cache artifact
        uses: actions/upload-artifact@b7c566a772e6b6bfb58ed0dc250532a479d7789f # v6.0.0
        if: "@@IF@@ && matrix.image_class == 'hostapp'"
        with:
          name: ${{ env.MACHINE }}-sstate
          path: /tmp/sstate.tar
          retention-days: 30
          compression-level: 0
          if-no-files-found: error

      - name: Verify kernel module signing key
'''
rep('''      - name: Verify kernel module signing key
''',
    _save.replace('@@IF@@', SSTATE_IF))

# ── P12v2: small jobs (approved-commit, balena-lib, all_jobs) must not land
# on GitHub-hosted runners while the repo is PRIVATE (billing-blocked ->
# silent assignment failure). Visibility-aware label: free ubuntu-24.04 when
# public, our self-hosted runner otherwise. Self-heals at the public flip.
rep("    runs-on: ubuntu-24.04\n",
    "    runs-on: ${{ github.event.repository.visibility == 'public' && 'ubuntu-24.04' || 'self-hosted' }}  # abrp: GH-hosted only when public\n",
    count=3)

# ── P22: maximize build space on ANY GitHub-hosted runner (not just
# ubuntu-latest — larger runners carry custom labels) ─────────────────────────
rep("        if: contains(fromJSON(inputs.build-runs-on), 'ubuntu-latest') == true",
    "        # abrp: any GH-hosted runner (larger runners carry custom labels)" + chr(10) + '        if: "!contains(join(fromJSON(inputs.build-runs-on), \',\'), \'self-hosted\')"')

# ── verify ──────────────────────────────────────────────────────────────────
import yaml
d = yaml.safe_load(t)
jobs = list(d['jobs'].keys())
assert jobs == ['approved-commit', 'balena-lib', 'build', 'all_jobs'], jobs
for j in jobs:
    n = d['jobs'][j].get('needs', [])
    assert 's3-deploy' not in n and 'source-mirror-setup' not in n and 'hostapp-deploy' not in n and 'ami-deploy' not in n, (j, n)
assert t.count('deploy-environment') == 0, 'deploy-environment reference left over'
assert t.count('force-finalize') == 1, 'force-finalize reference left over'  # 1 = the explanatory comment
assert 'minio' not in t and 'tespkg' not in t
maximize = [s for s in d['jobs']['build']['steps'] if s.get('name') == 'Maximize build space'][0]
assert 'self-hosted' in str(maximize.get('if')), 'maximize-build-space gate not rewritten'
assert any(str(s.get('with', {}).get('name', '')).endswith('-sstate') for s in d['jobs']['build']['steps']), 'sstate upload step missing'
assert 'apparmor_restrict_unprivileged_userns' in t, 'userns sysctl step missing'
p.write_text(t)
print(f"OK: {orig.count(chr(10))} -> {t.count(chr(10))} lines; jobs: {jobs}")
