# Contribute a useful change

Start with the [repository contributor guide](https://github.com/nix-forge/nix-conf/blob/main/CONTRIBUTING.md).
It explains ownership, module conventions, and validation. A guide improvement
can be a small pull request with a clear reader-visible result.

## Good first contributions

- Follow the starter on a listed platform and report the exact failing step.
- Explain an error message you encountered, with the smallest reproduction.
- Improve a recipe's expected output or prerequisite list.
- Add a consumer fixture for an independently reusable module before advertising it.

Avoid duplicating a long source listing in prose. The guide's embedded examples
are checked against their source files so readers see the tested configuration.
For a larger change, describe the intended result in an issue before taking on
work that may conflict with another contributor.

## Report a tutorial attempt

The guide-feedback form asks whether you completed the exercise, the step that
blocked you, your platform, and the source revision. Approximate time to the first
successful build is useful when you also state whether dependencies were cached.
No account identifiers, private configuration, or complete logs are needed.

These reports help us improve completion and reduce repeated support requests.
Stars and clone counts cannot tell us whether a tutorial worked.

Report vulnerabilities through the existing
[security policy](https://github.com/nix-forge/nix-conf/blob/main/SECURITY.md).
