# Cisco Identity Intelligence ISE Agent Quick Start

Use this guide to prepare Cisco ISE, install the on-premises agent, and verify
the first connection. For complete setup and troubleshooting guidance, see the
[Cisco ISE integration documentation](https://docs.oort.io/integrations/cisco-identity-services-engine-ise).

## Before you start

- Use Cisco ISE 3.3 or later with ERS, the required endpoint APIs, and pxGrid
  enabled.
- Prepare a dedicated, access-controlled host directory. The host needs Docker
  with Compose, or Podman with a Compose provider.
- Create a dedicated internal ISE administrator account for the agent. Assign
  **ERS Operator** and **MnT Admin**. Use **ERS Admin** instead of ERS Operator
  only if the integration needs to perform write actions.
- Allow the agent host to reach the configured ISE API port (TCP 443 by
  default) and the applicable ISE pxGrid nodes on TCP 8910.
- Allow outbound TCP 443 to the `IOT_ENDPOINT` included in `.env`, GitHub
  release and GHCR endpoints, and hosts used by signed S3 upload URLs. If a
  proxy is required, it must allow HTTP CONNECT on port 443; enter it as an
  `http://` URL during credential setup.
- In ISE, go to **Administration > pxGrid Services > Settings**, enable
  **Allow password based account creation**, and select **Save**. This setting
  is disabled by default and is separate from enabling pxGrid on a deployment
  node.
- Arrange for an ISE administrator to approve the agent's pxGrid client if you
  will create a new one.

## Required platform processes

This inventory applies to the supplied Docker or Podman deployment. The ISE
agent installs no host background service, `systemd` or `launchd` unit, or
scheduled task, and the supplied Compose configuration publishes no inbound
port. Only the container runtime, ISE agent launcher, and ISE agent application
are ISE-agent-owned continuous processes. Every other ISE-agent-owned process
listed below is transient and may be stopped when its stated operation is
complete. Platform DNS, time, networking, and runtime-helper dependencies are
described separately below.

| Administrator-visible process or command | Location and classification | Purpose | Effect if unavailable, restricted, or stopped |
|---|---|---|---|
| Docker Engine, Docker Desktop backend, or Podman container runtime | Customer host; essential and continuous | Runs the container, applies its restart policy, provides networking and persistent storage, and retains container logs | The agent stops collecting and sending data. A stopped runtime cannot restart the container after a host or process failure. |
| ISE agent launcher | Inside the container; essential and continuous | Starts and supervises the active signed application bundle, checks for application updates, accepts healthy updates, and rolls back an update that does not become ready | The container exits. The container runtime's `restart: always` policy attempts to restart it. |
| ISE agent application | Inside the container; essential and continuous under the launcher | Connects to Cisco Identity Intelligence and ISE, processes pxGrid events, performs scheduled collection, handles authorized commands, and publishes status and data | Collection, real-time session monitoring, commands, diagnostic uploads, and heartbeats stop. The launcher and runtime attempt recovery. |
| Docker Compose, `podman compose`, or `podman-compose` | Customer host; transient operator command | Creates, starts, stops, and recreates the ISE agent service from `docker-compose.yml` | Install, start, stop, reconfiguration, host-tool update, and rollback commands cannot complete. An already running container normally continues until the container runtime or container stops. |
| `start.sh` and `.launcher/agentctl` | Customer host; transient operator command | Validate prerequisites and coordinate bootstrap, configuration, image pulls, lifecycle operations, diagnostics, host-tool updates, and application rollback | The affected operator command fails. These scripts do not need to remain running after the command completes. |
| `curl` | Customer host; transient download command | Downloads release metadata and host tools over HTTPS | Copied-command installation and host-tool refresh fail. Normal collection is unaffected after verified tools are installed. |
| `sha256sum` or `shasum` | Customer host; transient verification command | Verifies downloaded host tools against the release checksum manifest | Installation or host-tool update fails closed. Normal collection is unaffected after verified tools are installed. |
| IoT bootstrap utility | Short-lived setup container during installation or first start | Redeems one-time bootstrap material and writes the agent identity, certificate, and configuration | A new installation cannot obtain its identity or start. The process is not needed after bootstrap succeeds. |
| ISE credential setup utility | Short-lived setup container during first start or reconfiguration | Validates ISE API and optional proxy access, then encrypts the ISE configuration | Initial configuration or reconfiguration fails. The running agent does not require this setup process. |
| pxGrid setup utility | Short-lived setup container during first start or pxGrid reconfiguration | Encrypts the pxGrid node name and optional existing-client password. New-client registration is performed later by the ISE agent application. | pxGrid configuration cannot be created or changed. The running agent does not require this setup process. |
| ISE agent update-control utility | Short-lived maintenance container while the service is stopped | Reports update-control capabilities, rolls back the active application bundle, or changes the signed-bundle update setting | Only the requested maintenance operation fails. It is not needed during normal collection. |
| `collect-logs` image command | Short-lived diagnostic container | Runs the application's diagnostic collector and writes a bounded archive to the invoking host command | On-demand diagnostic collection fails. Continuous collection and reporting are unaffected. |

### Process configuration and TCP/IP services

All network connections initiated by these processes are outbound. The ISE
agent does not provide an inbound TCP/IP service and the supplied Compose file
has no `ports` mapping.

| Process or command | Required or recommended configuration | TCP/IP services used; none are provided |
|---|---|---|
| Container runtime and Compose provider | Keep the runtime available while the agent is running. Use the supplied Compose settings, including `restart: always`, the `certs` mount, bounded `json-file` logging, and bridge networking unless host networking is required. Restrict runtime administration to authorized host administrators. Never mount or expose the runtime control socket inside the agent container. | The runtime pulls images from GHCR over outbound HTTPS/TCP 443. Its local or remote management interface is a customer platform service, not an ISE agent service. |
| `start.sh`, `.launcher/agentctl`, and `curl` | Keep the host's trusted CA bundle current. Run only from the protected installation directory using the released scripts. | Outbound HTTPS/TCP 443 to GitHub release endpoints. Image pulls performed through the runtime use outbound HTTPS/TCP 443 to GHCR. |
| `sha256sum` or `shasum` | One of these commands must be on `PATH`; do not bypass checksum verification. | No TCP/IP service. |
| ISE agent launcher | Preserve the supplied update trust material and runtime files. Signed-bundle update checks are enabled by default and can be changed with the documented controller commands. | Outbound HTTPS/TCP 443 to GHCR and its registry authentication endpoint for signed application updates. No listening service. |
| ISE agent application | Preserve `.env`, the mounted `certs` directory, and the generated endpoint and identity values. Configure `ISE_HTTPS_PROXY` only when an outbound proxy is required. | Outbound TLS to the configured ISE API port (TCP 443 by default); outbound TLS to applicable ISE pxGrid nodes on TCP 8910; outbound MQTT/TLS to `IOT_ENDPOINT` on `MQTT_PORT` (TCP 443 by default, or the explicitly configured port); and outbound HTTPS/TCP 443 to hosts in signed object-storage upload URLs. A configured proxy must accept HTTP CONNECT for these Internet destinations. No listening service. |
| IoT bootstrap utility | Protect the one-time token, use only its generated HTTPS endpoint, and complete redemption before the token expires. | Outbound HTTPS/TCP 443 to the generated bootstrap endpoint. No listening service. |
| ISE credential setup utility | Use the documented ISE roles, configured ISE port, and optional `http://` proxy URL. | Outbound TLS to the configured ISE API port, TCP 443 by default. When a proxy is configured, it also validates MQTT/TLS access to `IOT_ENDPOINT` through the proxy. No listening service. |
| pxGrid setup and update-control utilities | Run only through `start.sh`; both modify protected state in the mounted `certs` directory. | No TCP/IP service. The setup utility stores configuration; the continuous application performs pxGrid registration and network access. |
| `collect-logs` | Run only when diagnostics are required and protect the generated archive as sensitive operational data. | Outbound TLS to the configured ISE API port to collect permitted ISE diagnostics. No listening service. |

### Other customer-platform processes

| Platform service or common administrator-visible name | When it is needed and effect if disabled | Configuration and TCP/IP use |
|---|---|---|
| DNS resolver, such as the platform resolver, `systemd-resolved`, or `dnsmasq` | Required when any configured ISE, Cisco Identity Intelligence, GitHub, GHCR, proxy, or signed upload endpoint is a hostname. Disabling resolution prevents the corresponding connection. | Configure the container runtime and host with approved resolvers. DNS commonly uses outbound UDP or TCP 53; retain any different enterprise DNS transport required by the platform. |
| Trusted clock synchronization, such as `chronyd`, `ntpd`, `systemd-timesyncd`, or a platform/hypervisor clock service | Accurate time is required for TLS certificate validation, secure update downloads, event timestamps, and scheduling. The agent does not require a particular implementation. | Use the organization's approved time sources. NTP implementations commonly use outbound UDP 123; a platform-provided clock may require no agent-host network service. |
| DHCP client, commonly managed by NetworkManager, `systemd-networkd`, or `dhclient` | Required only when the customer host obtains its network configuration through DHCP. It is not a direct ISE agent dependency and may be disabled on a correctly configured static host. | Platform-dependent; DHCP commonly uses UDP 67 and 68. |
| 802.1X supplicant, such as `wpa_supplicant` | Required only when the customer network requires host 802.1X authentication. It is not a direct ISE agent dependency. | Configure according to the customer network policy. EAP over LAN is a link-layer protocol rather than a TCP/IP service. |
| Docker or Podman runtime helpers, such as `dockerd`, `containerd`, `containerd-shim`, `conmon`, and the configured OCI runtime | Required only as selected and started by the customer's container runtime. Disabling a required helper can stop or prevent restart of the agent container. | Retain, restrict, and patch the processes required by the runtime vendor's supported platform baseline. Their management and networking interfaces are platform services, not ISE agent services. |

The ISE agent does not require a host database, HTTP server, RPC binder, D-Bus
service, file server, syslog daemon, scheduler, or remote-management daemon. A
knowledgeable administrator may disable them when they are also unnecessary
for the host OS, container runtime, and customer's operational baseline.

On OpenShift or Kubernetes, the continuous and short-lived container-process
rows and network dependencies still apply. The cluster runtime, networking,
DNS, logging, scheduler, and controller processes replace the host runtime and
Compose rows; they are platform-owned and must be retained and secured
according to the cluster vendor's supported baseline.

## Protect the deployment material

The downloaded package and copied install command contain a sensitive,
one-time bootstrap token. Complete setup within 24 hours of generating them,
transfer them only to the intended agent host, and do not paste them into chat
or support tickets. If the token expires, reset the agent credentials in the
ISE integration and use the newly generated package or command.

Do not edit the tenant ID, agent ID, IoT endpoint, topic prefix, certificate,
or private key included with the deployment.

## Install the agent

Use a dedicated directory that does not contain unrelated environment,
certificate, Compose, or launcher files.

### Copied install command

```sh
mkdir -p ~/ise-agent
cd ~/ise-agent
# Paste the complete command copied from Cisco Identity Intelligence.
```

The installer creates the deployment files and starts first-run credential and
pxGrid setup. To run on a platform without an interactive terminal, use the
noninteractive setup below.

### Downloaded ZIP

Transfer the ZIP using your organization's approved secure method, extract the
complete package into a dedicated directory, and run:

```sh
cd ~/ise-agent
chmod +x ./start.sh
./start.sh
```

## Complete first-run setup

1. Enter the ISE hostname, username, password, and API port. The password is
   saved in the agent's encrypted credential store, not in `.env`.
2. Enter an outbound HTTPS proxy only if required. Use an `http://host:port`
   URL; the proxy must support HTTP CONNECT to port 443.
3. Choose how to configure pxGrid:
   - **Create a new pxGrid client:** accept `cii-agent` or enter a
     deployment-specific node name. After the agent starts, approve that client
     under **Administration > pxGrid Services > Client Management > Clients**.
   - **Use an existing client:** enter the name and password of a pxGrid client
     that is already registered and approved.

pxGrid is required for real-time session events and complete session data.

## Noninteractive setup

OpenShift and other container platforms that do not provide a terminal can
configure the ISE agent from secret-backed environment variables. Supply these
values to the agent container (or add them to `.env` before running
`./start.sh`):

```text
ISE_HOST=<ISE hostname>
ISE_USERNAME=<ISE administrator username>
ISE_PASSWORD=<ISE administrator password>
ISE_PORT=443
ISE_HTTPS_PROXY=<optional http://proxy-host:port URL>
PXGRID_NODE_NAME=cii-agent
PXGRID_PASSWORD=<optional password for an existing approved pxGrid client>
```

`ISE_HOST`, `ISE_USERNAME`, `ISE_PASSWORD`, and `PXGRID_NODE_NAME` are required
for a fully unattended first run. The port and proxy are optional.
`PXGRID_PASSWORD` is needed only when reusing an already registered and
approved pxGrid client; without it, the agent creates a client that an ISE
administrator must approve.

On startup, the ISE agent validates these values and writes encrypted
credentials to `/app/certs/.credentials.enc` and `/app/certs/.pxgrid.enc` only
when those files do not already exist. The files are published atomically;
existing encrypted files are preserved and take precedence. The `/app/certs`
volume must be persistent across pod or container replacement. The agent does
not copy plaintext credentials into generated files or emit them in logs. If
you put onboarding values in `.env`, protect that file as sensitive. After
both encrypted stores have been created, remove the onboarding values from
`.env` and recreate the container. For OpenShift or Kubernetes, remove the
onboarding entries from the workload Secret and recreate the workload so the
plaintext values are no longer present in the container environment. If no
values are supplied, the normal interactive setup remains available.

For a one-time IoT bootstrap on a platform without a terminal, provide the
bootstrap endpoint and token through a Secret and run the image's bootstrap
command from an init job or other preparation step:

```text
ISE_AGENT_BOOTSTRAP_ENDPOINT=https://<bootstrap-host>/<bootstrap-path>
ISE_AGENT_BOOTSTRAP_TOKEN=<one-time-token>
```

```sh
# Run this command in an init container using the ISE agent image.
python -u /app/bootstrap_iot.py --environment --output-dir /bootstrap
```

The output directory must be empty on the first run. The command creates the
generated `.env` and `certs/` files without prompting or overwriting existing
agent configuration. Docker Compose imports the generated `.env` file. On
OpenShift or Kubernetes, a mounted `.env` file is not imported automatically:
load its entries into the workload with `env` or `envFrom`, and mount the
generated `certs/` directory at `/app/certs`. After bootstrap succeeds, remove
the one-time token from the Secret and recreate any workload that received it.
Do not pass the bootstrap token to the long-running ISE agent container.

## Verify the connection

1. Confirm the agent container is running.
2. Follow its logs and confirm that it connects to IoT Core, pxGrid activates,
   the WebSocket connects, and collection starts.
3. Return to **Integrations** in Cisco Identity Intelligence, open the existing
   ISE integration, and select **Agent is running** after the first heartbeat
   appears.

To find the generated container name and inspect recent logs:

```sh
grep 'container_name:' docker-compose.yml

# Docker
docker compose ps
docker logs --tail 200 -f <container_name>

# Podman
podman ps
podman logs --tail 200 -f <container_name>
```

If pxGrid reports that it is waiting for approval, approve the displayed client
in ISE. For connection timeouts, verify DNS, routing, the configured ISE API
port, and TCP 8910 access to the applicable pxGrid nodes.
