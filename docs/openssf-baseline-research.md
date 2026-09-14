# OpenSSF baseline implementation research

Updated 2026-09-14.

## Question

What source-backed controls are required to move the nix-forge repositories
from OpenSSF Baseline 1 to Baseline 2 and Baseline 3, and which controls are
conditional on a repository publishing releases or compiled assets?

## Sources

The implementation uses the official OSPS Baseline version
[2026.08.28](https://baseline.openssf.org/versions/2026-08-28), the
[Best Practices Badge baseline criteria](https://github.com/ossf/best-practices-badge/blob/main/criteria/baseline_criteria.yml),
and the [Best Practices Badge documentation](https://github.com/ossf/best-practices-badge/blob/main/docs/criteria.md).
The BadgeApp project records for projects 14636 through 14642 were checked on
2026-09-14. The seven enrolled repositories were at Baseline 1 with unknown
Baseline 2 and 3 assertions before this work.

GitHub's [workflow event documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
states that workflows required by a merge queue must also listen for
`merge_group`. The DCO, dependency review, CodeQL, and repository CI workflows
therefore cover pull requests and merge-group refs.

## Implementation decisions

Baseline 2 requires contributor legal assertions, automated checks, tests,
dependency documentation, governance, vulnerability response, and release
documentation. The repositories now have a checked-in DCO policy and status
check, explicit least-privilege workflow permissions, a shared test and
dependency-review policy, threat models, governance evidence, and public VEX
files.

Baseline 3 adds per-job permissions, trusted-input handling, non-author review,
security assessment, supply-chain and SAST gates, release verification, and
support lifecycle documentation. The repository workflows already used most of
the required permission pattern. This change adds the missing DCO and coverage
where the organization repository and the shared CI repository needed their own
checks, then updates branch protection to require one non-author approval.

Release and compiled-asset controls are marked not applicable only for
repositories that do not publish that kind of artifact. `ci` and
`nix-config-framework` have source release histories, so their release process
is documented and their future release gates are treated as applicable. The
remaining source-only repositories describe the release conditions that would
apply before they publish an official release.

## Evidence locations

- `DCO` and `.github/workflows/dco.yml` enforce the legal contribution
  assertion.
- `.github/workflows/dependency-review.yml` and
  `.github/workflows/codeql.yml` provide SCA and SAST checks.
- `THREAT_MODEL.md` records assets, actors, trust boundaries, and release
  review triggers.
- `security/vex.json` provides a public place for non-affectability statements.
- `docs/openssf-baseline.md` records build, release, governance, support, and
  vulnerability-response policy.
- Protected `main` requires passing status checks, resolved conversations, and
  one approval from a human who did not author the pull request.
