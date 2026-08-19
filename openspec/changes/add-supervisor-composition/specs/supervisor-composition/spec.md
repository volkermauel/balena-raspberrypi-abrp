# supervisor-composition Specification Delta

## ADDED Requirements

### Requirement: Composition Deployment

The OS image SHALL deploy the supervisor composition (core-next and service-relay) alongside the single-container legacy supervisor, started by a dedicated systemd unit after `balena-supervisor.service` becomes active.

#### Scenario: Boot on a provisioned device

- **WHEN** a device boots and `balena-supervisor.service` is active
- **THEN** `balena-supervisor-next.service` brings up the `core-next` and `service-relay` containers from `/etc/balena-supervisor/supervisor-compose.yml`
- **AND** both containers have restart policy `always`

#### Scenario: First boot offline

- **WHEN** a device boots without network connectivity
- **THEN** the supervisor and helios images run from the preloaded docker-disk content
- **AND** no image pull is required for the composition to start

### Requirement: Proxy Environment Injection

The deployment SHALL provide helios the environment that the supervisor's feature-label machinery (`io.balena.features.*`) would normally inject, sourced from host config and the supervisor state database.

#### Scenario: Environment file generation

- **WHEN** `balena-supervisor-next.service` starts
- **THEN** `/run/supervisor-compose.env` contains `BALENA_DEVICE_UUID`, `BALENA_API_URL`, `BALENA_API_KEY`, `BALENA_SUPERVISOR_HOST` (10.114.104.1), `BALENA_SUPERVISOR_PORT`, and the supervisor's main API key extracted from its database
- **AND** composition start fails and retries if the supervisor container or its API key is unavailable

### Requirement: Supervisor Network Prerequisite

The deployment SHALL ensure the `supervisor0` network (bridge `supervisor0`, subnet `10.114.104.0/25`, gateway `10.114.104.1`) exists before the composition starts, using configuration identical to the supervisor's own `ensureSupervisorNetwork`.

#### Scenario: Fresh device without applied state

- **WHEN** the composition starts on a device where the supervisor has not yet applied a target state
- **THEN** `supervisor0` is created idempotently by the env script
- **AND** the supervisor can bind its API to `10.114.104.1:48480` after takeover

### Requirement: Reversible Takeover

The deployment SHALL be reversible: removing the composition restores direct supervisor-to-API communication.

#### Scenario: Rollback

- **WHEN** an operator disables `balena-supervisor-next.service`, removes the helios containers, deletes `apiEndpointOverride` and `listenPortOverride` from the supervisor config database, and restarts `balena-supervisor.service`
- **THEN** the supervisor listens on its standard port and communicates with the API directly
