# Threat model

## Scope

This model covers the reusable modules, the public starter, deployed host
examples, documentation build, and repository automation. A consumer's host,
credentials, hardware, and external services remain outside this repository's
control.

## Assets and actors

The main assets are module behavior, generated configurations, documentation,
dependency pins, and repository automation. Contributors and pull requests are
untrusted. Maintainers approve changes and control Pages, Actions, and future
releases. CI may evaluate pull-request code but must not receive repository
secrets. Consumers decide which modules to deploy and supply their own secret
backend.

## Trust boundaries

The Nix evaluator and generated system configuration are separate from GitHub
Actions. Host examples are separate from reusable modules. Secret-management
inputs are separate from public configuration. The documentation site is
public output and must not contain private host state.

## Main threats and controls

| Threat | Control |
| --- | --- |
| A reusable module introduces an unsafe default | Required tests, review, CodeQL, dependency review, and documented module contracts |
| A host example leaks private deployment data | Publication review, secret boundary tests, and no credentials in the repository |
| A workflow executes untrusted input with write access | Empty default permissions, job scopes, pinned actions, and no secrets in fork jobs |
| A dependency is compromised or has a known flaw | Lockfile review, dependency review, CodeQL, and release gating |
| Documentation gives unsafe deployment advice | Reviewed guides, threat-model updates, and Pages build checks |

Review this model when a module changes a trust boundary, a host example gains
new credentials or network access, or CI or release automation changes.
