# ISE Agent Host Repository Guidance

This repository owns the customer-distributed host package for the ISE agent:
installation, the stable `start.sh` bootstrap, the versioned `agentctl`
controller, Compose configuration, updates, rollback, and container lifecycle.
The application and collection implementation belongs in the companion
`duosecurity/ise-agent-container` image repository.

## Cross-repository changes

- Inspect any linked companion PR before approving a change that alters the
  host-to-image contract. Validate the exact submitted heads together.
- The image change must be published before a host change that depends on its
  new command or behavior. Account for installations that can temporarily run
  mismatched host tools and `latest` image versions.
- Keep a stable, documented image command interface. Do not make host tooling
  invoke image-private Python files with `--entrypoint` or bind-mount source
  code out of the image when a supported image command can provide the feature.

## Portability is a requirement

Treat portability regressions as blocking unless the PR explicitly changes
the supported-platform policy.

- Host tooling must work on supported Linux and macOS hosts, with both Docker
  and Podman, including rootful, rootless, Desktop, Podman Machine, and remote
  runtime configurations where the common CLI contract supports the operation.
- Use macOS system Bash 3.2 as the compatibility floor. Do not use Bash 4+
  features such as `[[ -v name ]]` or associative arrays. Be careful with empty
  arrays under `set -u` and validate the exact code path with Bash 3.2.
- Prefer common Docker/Podman CLI operations. Do not hard-code Unix socket
  locations or branch on host-specific runtime internals when the CLI can do
  the work.
- Do not solve bind-mount ownership with fixed UIDs, host-specific `chown`, or
  `--user` assumptions. Account for user namespaces and rootful runtimes.
- Do not mount the container runtime socket merely to collect container logs.
  A mounted runtime socket is effectively host-root access and is often absent
  or at a different path on Podman and desktop/remote runtimes.

## Keep the host boundary thin

The host controller should detect and invoke the runtime, provide required
mounts and networking, and manage the resulting host file. Put parsing,
defaults, validation, collection, temporary workspace management, manifest
creation, timestamping, and archive packaging inside the image.

For commands that produce an archive or other binary artifact:

- The image should build the artifact internally and stream it on stdout.
- Diagnostics must go to stderr, and the host invocation must not allocate a
  TTY when stdout is a machine-readable or binary interface.
- The host should set `umask 077`, redirect stdout to a host-created file, and
  remove a partial file when the container command fails.
- Avoid output-directory bind mounts whose ownership depends on the container
  runtime. Do not emit success until the artifact is complete and validated.
- Prefer image-owned defaults or the existing `.env` contract. Avoid adding
  host parameters that merely duplicate image configuration. Remember that a
  bare `-e NAME` can override an env-file value with the host environment.

## Host lifecycle and release safety

- Keep `start.sh` small and stable. Versioned lifecycle behavior belongs in
  `agentctl`; credential and ISE-specific behavior belongs in the image.
- Preserve checksum verification, atomic replacement, update locking, backup,
  rollback, executable modes, and cleanup on every failure path.
- Preserve user configuration during upgrades. Generated Compose changes must
  not silently discard `.env`, network mode, certificate mounts, or deliberate
  local overrides.
- Avoid persisting mutable runtime state only in image-baked `/app` paths. Any
  state that must survive image replacement needs an explicit persistent mount
  and a compatible migration/reset contract in the image.

## Review and validation

- Review the exact submitted PR head, current diff, checks, and unresolved
  threads. Re-fetch after updates instead of repeating findings from an older
  revision.
- Identify whether a problem is introduced by the PR, merely exposed by it, or
  speculative. Make review comments concrete and prescriptive.
- Run at least:

  ```sh
  bash -n install.sh start.sh agentctl tests/test-host-tools.sh
  tests/test-host-tools.sh
  ```

- Exercise new launcher paths with both mocked Docker and mocked Podman CLI
  behavior. Cover success, container-command failure, partial-output cleanup,
  file permissions, argument/env propagation, and update rollback as relevant.
- Linux CI is not evidence of macOS Bash compatibility. Run affected host paths
  with `/bin/bash` on macOS when they use nontrivial shell behavior.
- State validation scope precisely. A mocked launcher test is not a real image,
  runtime, ISE, networking, or end-to-end test.

## Security and customer-facing language

- Never log, archive, or expose credentials, private keys, bootstrap tokens, or
  decrypted secret values. Use restrictive permissions for generated files.
- Use the customer-facing term **ISE agent**, never the internal abbreviation
  **ICA**, in documentation, messages, artifact names, and new interfaces.
- Keep customer copy product- and transport-neutral unless implementation
  details are necessary for the task. Avoid exposing internal MQTT, AWS IoT,
  S3, or service names in setup and troubleshooting text.
