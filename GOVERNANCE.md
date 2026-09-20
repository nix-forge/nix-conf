# Governance

`nix-conf` is a maintainer-led open source project. The current maintainer is
[@IanHollow](https://github.com/IanHollow).

The repository contains reusable NixOS, nix-darwin, and Home Manager modules,
along with actively deployed configurations that serve as maintained examples.
Project direction should keep reusable behavior in shared modules and keep
hardware-specific policy in the example deployments.

Issues and pull requests are the public record for technical decisions. The
protected `main` branch, required checks, and merge queue apply to all accepted
changes. While this is a solo-maintainer project, GitHub requires no independent
approval; the maintainer may use AI review and authorize an agent to merge after
the checks pass. The [organization review policy](https://github.com/nix-forge/.github/blob/main/GOVERNANCE.md#solo-maintainer-review-and-automation)
also governs scheduled bot updates and privileged automation changes. Larger design changes should explain their user-facing
impact and migration path before implementation.

Code collaborators are reviewed before receiving escalated permissions for
protected-branch approval, repository administration, Pages, Actions secrets,
or release automation. The review considers sustained contribution quality,
identity or organizational affiliation where relevant, and the narrowest role
needed. Access is revisited when responsibility changes and removed promptly
when it ends.

The maintainer makes release and compatibility decisions. New maintainers may
be invited after sustained, constructive contributions and agreement on the
project's security and support expectations.

Report security issues through [SECURITY.md](SECURITY.md), not through public
issues or pull requests.
