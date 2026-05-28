# ISE Agent

On-premises agent for [Cisco Identity Intelligence](https://www.cisco.com/c/en/us/products/security/identity-intelligence.html). Connects your ISE deployment to Cisco Identity Intelligence.

## Requirements

- Docker (with Compose) or Podman
- Network access to your ISE API Gateway or ERS/MnT APIs
- Network access to ISE pxGrid on TCP `8910` when pxGrid session monitoring is enabled

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
./start.sh --enable-pxgrid  # Enable or reconfigure pxGrid session monitoring
./start.sh --disable-pxgrid # Disable pxGrid and use MnT polling
./start.sh --stop         # Stop the agent
```

### Multi-node ISE deployments

During credential setup, use the ISE node with API Gateway enabled. The setup
flow attempts to detect API Gateway nodes from ISE and lets you confirm the
selected API host.

During pxGrid setup, the agent probes known deployment nodes on TCP `8910`.
If pxGrid is enabled on a different node from the API Gateway node, enter the
pxGrid node IP or hostname when prompted. Multiple pxGrid hosts can be entered
as a comma-separated list for failover.

## Files

| File | Description |
|------|-------------|
| `install.sh` | Bootstrap script for one-line installation |
| `start.sh` | Start/stop the agent container |
| `docker-compose.yml` | Container definition (populated by install or ZIP package) |
