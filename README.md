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
3. Download the stable `start.sh` bootstrap, versioned `agentctl`, and `docker-compose.yml`
4. Start the agent

The generated `.env` only includes connection settings. The agent image applies
its built-in polling and telemetry cadence defaults unless you add optional
interval overrides to `.env`.

Alternatively, download the agent package ZIP from the UI and run `./start.sh` manually.

## Releasing

Every merge to `main` publishes a GitHub Release containing `install.sh`, the
stable `start.sh` bootstrap, versioned `agentctl`, `docker-compose.yml`, and
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
./start.sh --update       # Update host tools and the agent image, then restart
./start.sh --collect-logs # Collect ISE agent and selected ISE debug logs
./start.sh --stop         # Stop the agent
```

### Troubleshooting log collection

Use `./start.sh --collect-logs` when Cisco support asks for ISE agent
diagnostics. The command creates one host-owned archive under
`logs/ise-agent-logs-<timestamp>-<pid>.tar.gz` that can be attached to a support
case or shared with the troubleshooting team.

The archive includes the ISE agent container logs and the ISE debug logs commonly
needed to investigate agent connectivity and pxGrid issues. If some logs are not
available, the command records the error and still includes any logs it can
collect.

## Files

| File | Description |
|------|-------------|
| `install.sh` | Bootstrap script for one-line installation |
| `start.sh` | Stable bootstrap for the cached host controller |
| `agentctl` | Versioned Docker/Podman and Compose lifecycle controller |
| `docker-compose.yml` | Generated container definition (populated by install or update) |
