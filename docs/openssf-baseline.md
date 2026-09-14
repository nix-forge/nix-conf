# OpenSSF baseline policy

This repository follows the [OSPS Baseline](https://baseline.openssf.org/versions/2026-08-28)
version 2026.08.28. The policy applies to the reusable modules, deployed
configuration examples, documentation site, CI, and source history.

## Project scope

nix-conf publishes reusable NixOS, nix-darwin, and Home Manager modules. The
host definitions are maintained deployment examples, not installation
templates. This repository does not currently publish a compiled release
asset. A future source release must use a unique immutable tag, a change log,
integrity evidence, and the release process documented here before it is
announced.

## Change and build controls

Every commit must carry a matching `Signed-off-by` trailer. The `DCO` file
defines the certificate and `.github/workflows/dco.yml` checks proposed
non-merge commits on pull requests and merge-group refs.

All workflows start with `permissions: {}`. Jobs grant only the scopes they
need, checkout does not persist credentials, and actions use full commit SHAs.
Pull requests and merge groups run the required checks before protected `main`
can advance. CI includes flake lock health, dependency review, CodeQL,
repository hooks, generated documentation checks, and the test suites that
cover the affected configuration.

Use the repository's pinned development environment and run the smallest
affected checks from [docs/testing.md](testing.md). The normal baseline set is:

```console
nix flake check --show-trace
just hooks
python3 -m unittest discover -s tests
```

Host builds are evaluated separately from deployment. Never put credentials,
private identities, or plaintext secret fixtures in a flake, a test, or a
workflow. Major configuration changes add or update an observable test and
explain the migration in the pull request.

## Release and dependency controls

Flake inputs, nested lockfiles, package pins, and generated references are
reviewed with their security and compatibility impact. Dependency review blocks
new low-or-higher severity vulnerabilities. CodeQL findings and SCA findings
must be fixed before a future release unless a reviewed suppression records
why the finding is not exploitable.

If this repository begins publishing releases, the maintainer will create the
tag from reviewed `main`, publish a scoped change log, record the source
commit, and publish checksums and a signed manifest. The release note will
identify the actor and workflow, document public interfaces and security
changes, explain verification, state the support window, and link the threat
model. Releases will not contain host credentials or deployment state.

## Governance and vulnerability response

The maintainers listed in [GOVERNANCE.md](../GOVERNANCE.md) own repository
administration, Actions secrets, Pages, dependency policy, and any release.
Access to sensitive resources is granted after review of the contributor's
history and intended responsibility. New maintainers start with the narrowest
role needed and receive broader access only after review.

Report vulnerabilities through [SECURITY.md](../SECURITY.md) or GitHub private
vulnerability reporting. The maintainer acknowledges a report within three
business days, provides an initial assessment within seven days, and publishes
an advisory after a fix or documented mitigation is available. [security/vex.json](../security/vex.json)
records reviewed non-affectability statements. Support and end-of-life rules
are in [SUPPORT.md](../SUPPORT.md).

The operating procedures for [dependency management](dependency-management.md)
and [secret management](secret-management.md) are part of this policy. They
define the review, release-gate, storage, access, and rotation requirements
used to support the controls below.

## Control evidence

| Control area | Evidence |
| --- | --- |
| Least-privilege CI and trusted inputs | Empty default permissions, job scopes, pinned actions, quoted environment inputs, and no fork secrets |
| Releases and change logs | This release policy and the release-evidence template |
| Dependencies | `flake.lock`, nested lockfiles, dependency review, and CodeQL |
| Build and test instructions | [CONTRIBUTING.md](../CONTRIBUTING.md) and [docs/testing.md](testing.md) |
| Governance | [GOVERNANCE.md](../GOVERNANCE.md) |
| Contributor legal agreement | [DCO](../DCO) and `.github/workflows/dco.yml` |
| Security assessment | [THREAT_MODEL.md](../THREAT_MODEL.md) |
| Vulnerability response | [SECURITY.md](../SECURITY.md), private reporting, advisories, and [security/vex.json](../security/vex.json) |
| Public interfaces and release identity | Module and guide documentation, reviewed source commits, and future signed manifests |
| Support lifecycle | [SUPPORT.md](../SUPPORT.md) |

This file is reviewed when module contracts, CI trust, dependency policy, or
release behavior changes.
