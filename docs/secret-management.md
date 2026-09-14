# Secret management policy

This policy covers repository administration, GitHub Actions, local
development, documentation examples, and any future release automation in
nix-conf. The repository is public and must remain safe to fork and inspect.

## Storage and handling

Secrets, private identities, credentials, and deployment state belong in the
consumer's secret backend or in GitHub's protected repository or environment
secret stores when automation genuinely requires them. They must never be
committed, placed in the Nix store, embedded in a flake or example, passed as
command-line arguments, or printed in logs, artifacts, tests, issues, or pull
requests.

Pull-request workflows, including workflows for forks, receive no repository
secrets. The current checks are designed to run without them. If release
automation later needs cloud access, it will use short-lived GitHub OIDC
credentials and an explicitly protected environment rather than a long-lived
key.

## Access and review

Repository administrators review Actions secrets, environments, Pages, and
future release access before granting it. Access begins at the narrowest role
needed, is individual rather than shared, and is removed when responsibility
ends. New secret use requires a pull request documenting its purpose, scope,
workflow, and failure behavior without exposing its value.

## Rotation and incident response

Secrets are rotated at least annually and immediately when a maintainer,
provider, workflow trust boundary, or authorization scope changes. Suspected
exposure triggers revocation, replacement, log and artifact review, and a
private vulnerability report or incident record. Rotation must not publish an
old or replacement value in repository history.

`security/vex.json` contains only reviewed non-affectability statements. It
must never contain secret values or private deployment details.

