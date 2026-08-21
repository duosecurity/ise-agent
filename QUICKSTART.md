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
pxGrid setup.

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
