# Dependency management policy

This policy applies to the reusable Nix modules, deployed examples, nested
flakes, GitHub Actions, and documentation tooling in nix-conf. Dependency
changes are reviewed as changes to the code and configuration trust boundary.

## Inventory and provenance

The authoritative dependency records are `flake.lock`, nested lockfiles under
`flake/`, `templates/`, and `packages/`, package source hashes, and immutable
action references in `.github/workflows/`. Each update identifies the source,
new revision, and material transitive or generated changes. Consumers are
expected to use the committed lockfiles when reproducing the examples.

Dependabot and the repository's lock-health checks keep supported inputs
visible. Dependency-review and CodeQL run in CI where GitHub supports the
repository's manifests and languages. The flake checks and repository hooks
cover the Nix-specific dependency surface and generated documentation.

## Selection and review

Maintainers review upstream provenance, maintenance status, security
advisories, licensing, platform compatibility, and configuration behavior.
Lockfiles and source hashes are updated together with their declarations.
Action updates use immutable commit SHAs. A change that alters a module
interface or deployed default includes a migration note and an affected
example or test.

## Release gate and exceptions

Before a future release, applicable dependency-review, CodeQL, lock-health,
flake, hook, and test checks must pass. A high- or critical-severity finding,
an unreviewed license problem, or a failed provenance check blocks release.
The only exception is a reviewed, time-bounded pull-request record that names
the component, explains why it is not exploitable here, assigns an owner, and
sets a remediation date. `security/vex.json` records reviewed
non-affectability statements in OpenVEX form; it does not waive an affectable
finding.

## Update and rollback

Updates are evaluated on the supported systems and representative examples.
A regression is rolled back by reverting the lockfile and declaration change,
then tracked with a follow-up issue. Emergency security updates use the
smallest safe change and receive normal review retrospectively if immediate
action is required.

