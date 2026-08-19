# Change Proposal: add-supervisor-composition

## Why

The upstream supervisor v19 ships as a composition (`core`, `core-next`, `service-relay`) that enables the helios "strangler fig" migration: core-next (helios) proxies all traffic between the legacy supervisor and the cloud, enabling queued OS updates, differential reporting, and progressive feature takeover. Our fleet builds (openBalena backend) deploy the supervisor as a single container via `balena-supervisor.service` — the composition never reaches the device because openBalena has no supervisor fleets or `/v6/supervisor_release` resource.

## What Changes

Deploy the supervisor composition device-side in the OS image:

- Add a `docker-compose` binary recipe (docker/compose v5.5.0, aarch64, checksum-pinned).
- Add `supervisor-compose.yml` (core-next + service-relay only; `core` stays a single container started by `balena-supervisor.service`) rendered at build time with a pinned `HELIOS_VERSION`.
- Add `balena-supervisor-next.service` which runs `docker compose up` after the supervisor starts, plus `supervisor-compose-env.sh` which waits for the supervisor, extracts its API key from its sqlite DB, and ensures the `supervisor0` network exists.
- Preload the helios image in the docker-disk build so devices boot fully offline.
- Make the helios image runtime-overridable via `/mnt/state/supervisor-compose.override` (build-time `HELIOS_VERSION` stays the default; a reflash/HUP no longer pins helios).
- Add a control plane update mechanism: CI pairs supervisor + helios into one versioned release (`controlplane-{supervisor,helios}:<supver>-h<heliosver>` on GHCR, stamped with a pair label), and `update-controlplane` on device applies a pair atomically — following the `:stable` channel daily via a timer (remote fleet-wide push) or an explicit tag via SSH (canary/rollback).

##Impact

- Devices gain the helios proxy: supervisor API traffic flows `supervisor → 127.0.0.1:48484 (relay) → helios → openBalena API`, with helios intercepting target-state requests.
- Takeover is persistent: helios writes `apiEndpointOverride`/`listenPortOverride` into the supervisor DB and re-binds the supervisor API to `10.114.104.1:48480`. See design.md for the rollback procedure.
- Supervisor and helios can be updated remotely without reflashing: move `:stable` (fleet, within ~24h) or `balena ssh` + `update-controlplane <pair>` (immediate). Version lockstep is enforced by the pair tag + labels, so a half-finished registry push is skipped on device.
- No changes to how user applications are deployed or updated.
