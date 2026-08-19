#!/bin/sh

# Prepare the environment file for the supervisor composition
# (core-next/service-relay) and ensure its prerequisites.
#
# ExecStartPre of balena-supervisor-next.service. Writes
# /run/supervisor-compose.env consumed by docker-compose --env-file.

set -o nounset

ENV_FILE=/run/supervisor-compose.env

# balena-config-vars provides: UUID, API_ENDPOINT, DEVICE_API_KEY, LISTEN_PORT
# shellcheck disable=SC1091
. /usr/sbin/balena-config-vars

LISTEN_PORT="${LISTEN_PORT:-48484}"

# Wait for the supervisor container: the takeover requires it and its API
# key is read from its state database
TIMEOUT=60
ELAPSED=0
until balena inspect --format '{{.State.Running}}' balena_supervisor 2>/dev/null | grep -q true; do
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "Timed out waiting for balena_supervisor container" >&2
        exit 1
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Extract the supervisor's main API key from its state database, using the
# same mechanism as the helios takeover script (sqlite3 module in the
# supervisor container, /data/database.sqlite is the supervisor's data dir)
SUPERVISOR_API_KEY=$(balena exec balena_supervisor node --input-type=module -e 'import sqlite3 from "sqlite3"; const db = new sqlite3.Database("/data/database.sqlite"); db.all("SELECT value FROM config WHERE key = ?", ["apiKey"], (e, r) => { if (e) { console.error(e.message); process.exit(1); } if (!r.length) { process.exit(1); } console.log(r[0].value); process.exit(0); });' 2>/dev/null | tail -n 1)

if [ -z "$SUPERVISOR_API_KEY" ]; then
    echo "Could not retrieve supervisor API key" >&2
    exit 1
fi

# Ensure the supervisor network exists with the exact configuration the
# supervisor itself expects (network-manager.ts supervisorNetworkReady):
# this guarantees the gateway IP exists before the supervisor re-binds its
# API to 10.114.104.1 after the takeover restart, even on devices that have
# not applied a target state yet. Creating it with identical options makes
# the supervisor treat it as its own.
if ! balena network inspect supervisor0 >/dev/null 2>&1; then
    echo "Creating supervisor0 network"
    balena network create \
        --driver bridge \
        --opt com.docker.network.bridge.name=supervisor0 \
        --subnet 10.114.104.0/25 \
        --gateway 10.114.104.1 \
        supervisor0
fi

# Host OS metadata (best effort, used by helios for reporting/HUP)
OS_VERSION=$(sed -n 's/^VERSION_ID="\(.*\)"/\1/p' /etc/os-release 2>/dev/null || true)


# Helios image: build-time default (rendered from HELIOS_VERSION), with an
# optional runtime override from the state partition. The override survives
# reboots and host OS updates without reflashing:
#   echo 'HELIOS_IMAGE=ghcr.io/balena-io/helios:0.26.0' \
#       > /mnt/state/supervisor-compose.override
#   systemctl restart balena-supervisor-next
# A new tag is pulled automatically by compose (default pull policy
# "missing"; the build-time default is preloaded for offline first boot).
OVERRIDE_FILE=/mnt/state/supervisor-compose.override
HELIOS_IMAGE="ghcr.io/balena-io/helios:@HELIOS_VERSION@"
if [ -f "$OVERRIDE_FILE" ]; then
    # Validate in a subshell first: a syntax error or unset-variable
    # reference inside a sourced file would abort this script
    if ( . "$OVERRIDE_FILE" ) 2>/dev/null; then
        # shellcheck disable=SC1090
        . "$OVERRIDE_FILE"
        echo "Using HELIOS_IMAGE override from $OVERRIDE_FILE"
    else
        echo "WARNING: $OVERRIDE_FILE failed validation, using build-time default" >&2
    fi
fi
# Reject empty or unsafe values (whitespace/newlines would corrupt the
# env file); image references use this charset (host[:port]/path:tag@digest)
case "$HELIOS_IMAGE" in
    *[!A-Za-z0-9._:/@-]*|'')
        echo "WARNING: rejecting unsafe HELIOS_IMAGE value, using build-time default" >&2
        HELIOS_IMAGE="ghcr.io/balena-io/helios:@HELIOS_VERSION@"
        ;;
esac
umask 077
cat > "$ENV_FILE" <<EOF
BALENA_DEVICE_UUID=${UUID}
BALENA_API_URL=${API_ENDPOINT}
BALENA_API_KEY=${DEVICE_API_KEY}
BALENA_SUPERVISOR_HOST=10.114.104.1
BALENA_SUPERVISOR_PORT=${LISTEN_PORT}
BALENA_SUPERVISOR_API_KEY=${SUPERVISOR_API_KEY}
BALENA_HOST_OS_VERSION=${OS_VERSION}
HELIOS_IMAGE=${HELIOS_IMAGE}
EOF

echo "Supervisor composition environment ready"
