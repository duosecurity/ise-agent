# ISE Agent

On-premises agent for [Cisco Identity Intelligence](https://www.cisco.com/c/en/us/products/security/identity-intelligence.html). Connects your ISE deployment to Cisco Identity Intelligence.

## Requirements

- Docker (with Compose) or Podman
- Network access to your ISE ERS/MNT APIs

## Installation

The easiest way to install is via the one-line command provided in the Cisco Identity Intelligence UI after creating an ISE integration. The command looks like:

```sh
curl -fsSL "https://github.com/duosecurity/ise-agent/releases/latest/download/install.sh" | bash -s "<bundle>"
```

This will:
1. Decode your IoT credentials from the bundle
2. Write `.env` and `certs/` to `~/ise-agent/`
3. Download the customer quick-start guide, stable `start.sh` bootstrap, versioned `agentctl`, and `docker-compose.yml`
4. Start the agent

The generated `.env` only includes connection settings. The agent image applies
its built-in polling and telemetry cadence defaults unless you add optional
interval overrides to `.env`.

Alternatively, download the agent package ZIP from the UI and run `./start.sh` manually.

### Resume interrupted host setup

For installations created with this host-tool release, a failed ISE credential,
pxGrid configuration, or container-start step retains the saved cloud certificate,
key, and completed configuration. Run this command in the same installation directory:

```sh
./start.sh --resume
```

Resume stops the service before running the image's ISE and pxGrid setup commands,
then starts the service. Interactive setup asks for credentials again; existing
encrypted stores retain the image's existing noninteractive behavior. A missing
pxGrid store is configured even when the ISE store already exists. No automatic
password retry loop is added, and no cloud enrollment is revoked.

The private `.launcher/setup.pending` file records the interrupted host step.
Ordinary start and update commands direct an incomplete installation to
`--resume`; stop and log collection remain available. A lock prevents concurrent
host setup sessions. After an abrupt process termination, confirm no setup is
running before removing an abandoned `.launcher/setup.lock` directory.

The host clears its pending marker when Compose accepts the start request.
This does **not** establish cloud authorization or pxGrid readiness: verify the
agent's cloud connection, pxGrid activation, and heartbeat before considering
installation complete. Authentication happens in the existing agent image; this
repository adds no certificate or cloud-authorization preflight interface.

If the cloud deployment was deleted or its credentials reset, do not resume the
old directory. Stop that deployment, obtain a fresh package, and install into a
new dedicated directory. The installer refuses to overwrite saved identity and
does not automatically redeem a replacement token over it. It also accepts
`--resume` to delegate to an already installed launcher.

This flow applies to the Docker/Podman host tools. It does not change the ISE
appliance `application install` CLI, which belongs to `sbg-ise-agent-infra`.

## Releasing

Every merge to `main` publishes a GitHub Release containing `install.sh`, the
customer `QUICKSTART.md`, stable `start.sh` bootstrap, versioned `agentctl`,
`docker-compose.yml`, and
SHA-256 checksums. The workflow creates a commit-specific
`release-<commit>` tag automatically, so no manual tag is required.

`./start.sh --update` downloads and verifies the latest host tools, validates
the scripts and rendered Compose configuration, saves the previous files under
`.launcher/previous/`, then pulls the current agent image and restarts it. An
ordinary start uses the cached controller and therefore does not require access
to GitHub.

Existing installations need one launcher migration before host tools can update
themselves:

```sh
curl -fsSL "https://github.com/duosecurity/ise-agent/releases/latest/download/start.sh" -o start.sh
chmod +x start.sh
./start.sh --update
```

Keep customer configuration in `.env`. If a deployment needs Compose
customization, put it in `docker-compose.override.yml`; the generated base
`docker-compose.yml` is replaced during host-tool updates.

## Usage

```sh
./start.sh                # Start the agent (prompts for ISE credentials on first run)
./start.sh --reconfigure  # Re-enter ISE credentials
./start.sh --resume       # Resume setup using the saved cloud enrollment
./start.sh --update       # Update host tools and the agent image, then restart
./start.sh --rollback     # Roll back to the retained previous application bundle
./start.sh --enable-auto-updates  # Enable signed application-bundle update checks
./start.sh --disable-auto-updates # Disable checks without changing the active version
./start.sh --collect-logs # Collect ISE agent and selected ISE debug logs
./start.sh --stop         # Stop the agent
./start.sh --help         # Show all available commands
```

Rollback stops the service, validates that the installed image supports manual
bundle rollback, activates the retained previous bundle, and restarts the
service. It rolls back application code within the current image; reverting the
container runtime or image-level dependencies requires selecting an older image.
The enable and disable commands use the same image-owned control interface and
persist the setting in the existing certificates volume; host tooling does not
parse Compose image ordering or rewrite customer environment files.

### Troubleshooting log collection

Use `./start.sh --collect-logs` when Cisco support asks for ISE agent
diagnostics. The command creates one host-owned archive under
`logs/ise-agent-logs-<timestamp>-<pid>.tar.gz` that can be attached to a support
case or shared with the troubleshooting team.

The archive includes the ISE agent container logs and the ISE debug logs commonly
needed to investigate agent connectivity and pxGrid issues. If some logs are not
available, the command records the error and still includes any logs it can
collect.

### pxGrid account creation returns HTTP 503

The ISE agent registers a password-based pxGrid client on first start. If the
agent logs report that pxGrid `AccountCreate` returned HTTP 503, verify these
settings in ISE:

1. Under **Administration > pxGrid Services > Settings**, enable
   **Allow password based account creation**.
2. Under **Administration > System > Deployment**, verify that the pxGrid
   persona is enabled on at least one node.
3. Restart the ISE agent, then approve the pending `cii-agent` client under
   **Administration > pxGrid Services > Client Management > Clients**.

## Files

| File | Description |
|------|-------------|
| `install.sh` | Bootstrap script for one-line installation |
| `QUICKSTART.md` | Customer setup guide installed as `README.md` by curl and ZIP installations |
| `start.sh` | Stable bootstrap for the cached host controller |
| `agentctl` | Versioned Docker/Podman and Compose lifecycle controller |
| `docker-compose.yml` | Generated container definition (populated by install or update) |
