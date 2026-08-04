# ISE Agent

On-premises agent for [Cisco Identity Intelligence](https://www.cisco.com/c/en/us/products/security/identity-intelligence.html). Connects your ISE deployment to Cisco Identity Intelligence.

## Requirements

- Docker (with Compose) or Podman
- Network access to your ISE ERS/MNT APIs

## Installation

The easiest way to install is via the one-line command provided in the Cisco Identity Intelligence UI after creating an ISE integration. The command looks like:

```sh
curl -fsSL "https://github.com/duosecurity/ise-agent/releases/latest/download/install.sh" | bash
```

This will:
1. Download `docker-compose.yml` and `start.sh`
2. Prompt securely for the CII agent credential and your ISE credentials
3. Encrypt the credentials on the host
4. Start the agent

The generated `.env` contains no credentials. The agent image applies its
built-in polling and telemetry cadence defaults unless you add optional interval
overrides to `.env`.

Alternatively, download the agent package ZIP from the UI and run `./start.sh` manually.

## Releasing

Every merge to `main` publishes a GitHub Release containing `install.sh`,
`start.sh`, and `docker-compose.yml`. The workflow creates a commit-specific
`release-<commit>` tag automatically, so no manual tag is required.

## Usage

```sh
./start.sh                # Start the agent (prompts for ISE credentials on first run)
./start.sh --reconfigure  # Re-enter ISE credentials
./start.sh --stop         # Stop the agent
```

## Files

| File | Description |
|------|-------------|
| `install.sh` | Bootstrap script for one-line installation |
| `start.sh` | Start/stop the agent container |
| `docker-compose.yml` | Container definition (populated by install or ZIP package) |
