# ISE Agent

On-premises agent for [Cisco Identity Intelligence](https://www.cisco.com/c/en/us/products/security/identity-intelligence.html). Connects your ISE deployment to Cisco Identity Intelligence.

## Requirements

- Docker (with Compose) or Podman
- Network access to your ISE ERS/MNT APIs

## Installation

The easiest way to install is via the one-line command provided in the Cisco Identity Intelligence UI after creating an ISE integration. The command looks like:

```sh
curl -fsSL "https://raw.githubusercontent.com/duosecurity/ise-agent/v0.1/install.sh" | bash -s "<bundle>"
```

This will:
1. Decode your IoT credentials from the bundle
2. Write `.env` and `certs/` to `~/ise-agent/`
3. Download `docker-compose.yml` and `start.sh`
4. Start the agent

Alternatively, download the agent package ZIP from the UI and run `./start.sh` manually.

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
