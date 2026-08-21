ISE Agent Quick Start
=====================

The ISE agent connects your Cisco ISE deployment to Cisco Identity Intelligence.

Before you begin
----------------

- Install Docker with Compose or Podman.
- Make sure this server can reach your ISE deployment and has outbound HTTPS access.
- Complete setup within 24 hours of generating the agent package or install command.
  The included one-time setup credential expires after 24 hours and cannot be reused.

Install from the downloaded ZIP
-------------------------------

1. Extract the ZIP and open a terminal in the extracted directory.
2. Run: ./start.sh
3. Enter the requested ISE credentials.
4. Choose whether the agent should create a new pxGrid client or use an existing,
   registered and approved pxGrid client.
5. If the agent creates a client, approve it in ISE under:
   Administration > pxGrid Services > Client Management > Clients
6. Return to Cisco Identity Intelligence and confirm that the agent is running.

Install from the copied command
-------------------------------

Run the complete command copied from Cisco Identity Intelligence. The installer
places this guide and the agent files in the current directory, then starts the
same interactive setup described above.

Expired setup credential
------------------------

If setup reports that the credential has expired, return to the ISE integration
in Cisco Identity Intelligence, reset the agent credentials, and use the newly
generated package or install command. Do not reuse an older package or command.

Common commands
---------------

./start.sh                 Start the ISE agent
./start.sh --reconfigure   Re-enter ISE credentials
./start.sh --update        Update the host tools and agent
./start.sh --collect-logs  Collect diagnostics requested by Cisco support
./start.sh --stop          Stop the ISE agent
./start.sh --help          Show all supported commands
