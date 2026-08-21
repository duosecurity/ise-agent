# ISE Agent Host Repository Guidance

This repository owns the customer-installed host layer for the ISE agent. It
is responsible for installation, updates, rollback, configuration handoff, and
container lifecycle. The companion `duosecurity/ise-agent-container` repository
owns the application and collection behavior inside the image.

## Architecture and ownership

- Keep the host layer thin. It may adapt the host environment to the container
  runtime, but it should not duplicate application logic from the image.
- For onboarding, documentation, and setup-only improvements, target new
  installations by default. Do not make existing customers perform a manual
  host-tool or agent update unless the user explicitly requests it or the
  update is strictly necessary for correctness or security. If a manual update
  is unavoidable, explain the necessity before implementing it.
- Put parsing, business rules, collection behavior, artifact construction, and
  other application-specific work in the image behind a stable public
  interface.
- Do not couple host tooling to image-private source paths or implementation
  details. Treat the image interface as a versioned cross-repository contract.
- Review linked host and image changes together. Account for deployment order
  and temporary version skew between independently released repositories.
- Preserve customer configuration and provide safe failure, cleanup, update,
  and rollback behavior for lifecycle changes.

## Portability is a requirement

Treat avoidable host-OS or container-runtime coupling as blocking unless the PR
explicitly changes the supported-platform policy.

- Support the repository's documented Linux and macOS environments and both
  Docker and Podman through their common CLI behavior.
- Account for rootful, rootless, desktop-VM, user-namespace, and remote-runtime
  configurations. Do not assume a particular host UID/GID, filesystem layout,
  daemon socket, or ownership mapping.
- Use the oldest documented host shell as the compatibility floor. Avoid newer
  shell features unless support requirements and validation are updated in the
  same change.
- Prefer capability detection and standard runtime interfaces over OS names,
  hard-coded runtime internals, or runtime-specific branches.
- Do not mount a container-runtime control socket unless the feature truly
  requires privileged runtime access and no safer portable interface exists.
- Design host-visible outputs so their ownership, permissions, completeness,
  and cleanup do not depend on how the runtime maps container users.

## Review and validation

- Review the exact submitted PR head, current diff, checks, and unresolved
  threads. Re-fetch after updates instead of repeating stale findings.
- Distinguish regressions introduced by the PR from pre-existing behavior and
  from unverified risk. Make comments concrete and prescriptive.
- Discover the current validation entry points from repository scripts,
  documentation, and CI rather than relying on remembered command names.
- Validate every affected supported host/runtime boundary. A passing Linux CI
  job does not establish macOS shell compatibility, and a Docker-only test does
  not establish Podman compatibility.
- Exercise relevant success and failure paths, including cleanup, permissions,
  configuration propagation, updates, and rollback.
- Describe evidence precisely. Mocked host tests are not proof of a real image,
  runtime, network, ISE deployment, or end-to-end customer flow.

## Security and customer-facing language

- Never expose credentials, private keys, bootstrap tokens, decrypted values,
  or other secrets in logs, generated artifacts, tests, or review output.
- Grant generated files and runtime access no more privilege than required.
- Use the customer-facing term **ISE agent**, never the internal abbreviation
  **ICA**, in documentation, messages, artifacts, and new interfaces.
- Keep customer copy product- and transport-neutral unless an implementation
  detail is necessary for the customer task.
