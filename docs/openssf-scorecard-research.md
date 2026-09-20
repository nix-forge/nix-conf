# OpenSSF Scorecard rollout research

Reviewed: 2026-09-14. Scope: the public repositories in the `nix-forge` GitHub organization and the current upstream OpenSSF Scorecard Action workflow. This note supports maintaining the organization's Scorecard rollout, not changing it.

## Answer

`nix-forge` already has the intended baseline in six of its eight public repositories: `nix-conf`, `nix-homelab`, `vpn-confinement`, `nixpkgs-personal`, `nix-config-framework`, and `nix-seal` each run a SHA-pinned Scorecard workflow on `main`, weekly, and when branch-protection rules change. The public `ci` and `.github` repositories do not currently expose a Scorecard workflow. This is an observation from GitHub's public REST API and the default-branch workflow files, retrieved on 2026-09-14. It does not establish the state of private repositories.

For normal public source repositories, retain the upstream pattern: a default-branch `push` plus a weekly `schedule`, top-level read-only permissions, a dedicated Ubuntu-hosted analysis job, `contents: read`, `security-events: write`, and `id-token: write` when `publish_results: true`. Pin every third-party action to a full commit SHA and annotate it with the release version. The current upstream example pins `ossf/scorecard-action` at v2.4.4. It is a good baseline, although the SHA must be rechecked when updating because an upstream example can change after this review.

Do not make pull-request execution the standard rollout. The Scorecard Action documents `push` and `schedule` on the default branch as supported, calls `pull_request` experimental, and does not support running in a fork repository. If a repository deliberately tries the experimental trigger, use `pull_request`, never `pull_request_target`, do not add secrets or a PAT, and treat a failed or non-uploading fork PR run as expected until upstream documents support.

## Findings and sources

### Current upstream baseline

Facts:

- [OpenSSF's maintained example workflow](https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/.github/workflows/scorecard-analysis.yml) uses `push` restricted to `main` and a Saturday weekly schedule. It sets `permissions: read-all`, runs on `ubuntu-latest`, grants only `security-events: write` and `id-token: write` to the analysis job, disables checkout credential persistence, publishes results, uploads an optional five-day artifact, and uploads SARIF to code scanning.
- At review time, that example pins `actions/checkout` v7.0.1 to `3d3c42e5aac5ba805825da76410c181273ba90b1`, `ossf/scorecard-action` v2.4.4 to `2d1146689b8cda280b9bc96326124645441f03bc`, `actions/upload-artifact` v7.0.1 to `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`, and `github/codeql-action/upload-sarif` v4.37.7 to `ff2f1c621b7f889edc0d3c761ac2e6a3f8cdb0dd`.
- GitHub says a full commit SHA is the only immutable action release reference and offers repository and organization policies that require full-SHA pins. The SHA should be verified as belonging to the action's canonical repository. [GitHub secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions).
- The Action's own setup workflow is not its recommended consumer template. It deliberately references `ossf/scorecard-action@main` for pre-release testing. Use the maintained [Scorecard example](https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/.github/workflows/scorecard-analysis.yml), whose action versions are fixed by SHA, instead.

Inference: use the full-SHA convention for all four actions, even when a release tag is convenient. It gives an auditable update boundary and matches GitHub's security guidance. Track the version comment with the SHA so automated dependency updates and reviewers can tell what is changing.

### Permissions, result publication, and SARIF

Facts:

- `security-events: write` is required to upload SARIF through `github/codeql-action/upload-sarif`. GitHub's SARIF instructions also say private-repository uploads need `actions: read` and `contents: read`. [Uploading a SARIF file to GitHub](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/integrate-with-existing-tools/upload-sarif-file).
- `publish_results: true` enables Scorecard's published results and badge. Since Action v2 it also requires `id-token: write`, which lets the Action obtain a GitHub OIDC token to authenticate the published result. [Scorecard Action README](https://github.com/ossf/scorecard-action/blob/2d1146689b8cda280b9bc96326124645441f03bc/README.md#breaking-changes-in-v2).
- When publishing, the Action rejects workflows that have top-level `env` or `defaults`, workflow-level write permissions, or `id-token: write` outside the Scorecard job. The Scorecard job cannot have job-level `env` or `defaults`, containers, or services; must use an Ubuntu GitHub-hosted runner; and may contain only the documented approved actions. [Action workflow restrictions](https://github.com/ossf/scorecard-action/blob/2d1146689b8cda280b9bc96326124645441f03bc/README.md#workflow-restrictions).
- For private repositories, the Action recommends additional job-level `contents: read`, `issues: read`, `pull-requests: read`, and `checks: read` permissions to avoid GraphQL and SAST-detection gaps. Its private-repository support requires GitHub Advanced Security. A private repository without it can run the CLI instead. [Action private-repository guidance](https://github.com/ossf/scorecard-action/blob/2d1146689b8cda280b9bc96326124645441f03bc/README.md#additional-permissions-for-private-repositories).
- The default `GITHUB_TOKEN` is the Action's recommended authentication path. A narrowly scoped fine-grained PAT is optional only for classic branch-protection visibility or the experimental webhook check: `Administration: read` is needed for classic branch protection and `Webhooks: read` is optional. The Action warns that a classic `repo` token has greater risk. [Fine-grained PAT instructions](https://github.com/ossf/scorecard-action/blob/2d1146689b8cda280b9bc96326124645441f03bc/docs/authentication/fine-grained-auth-token.md).
- Repository rulesets are readable by the default token, while classic branch-protection detail needs the additional token. The Action recommends rulesets for new repositories. [Action authentication guidance](https://github.com/ossf/scorecard-action/blob/2d1146689b8cda280b9bc96326124645441f03bc/README.md#authentication-with-fine-grained-pat-optional).
- GitHub advises top-level read-only token access and minimum job-level additions. [GITHUB_TOKEN guidance](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token#modifying-the-permissions-for-the-github_token).

Inference: for a public repository, `permissions: {}` at workflow level plus explicit job-level `contents: read`, `security-events: write`, and `id-token: write` is equivalent in intent to upstream's `read-all` plus the two writes, while being more explicit about the checkout read. It is suitable for the organization's present workflows. Do not add a PAT merely to improve a score if rulesets can supply the branch-policy evidence.

Uncertainty: GitHub's SARIF documentation calls `actions: read` and `contents: read` private-only upload requirements, while the Scorecard Action separately recommends more read scopes for its own private GraphQL calls. Validate the exact private plan and entitlement in a non-production private repository before treating that permission set as complete.

### Organization-wide controls and their boundary

Facts:

- GitHub can require full-length SHA pins and restrict which actions and reusable workflows organization repositories may use. [Organization Actions settings](https://docs.github.com/en/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization).
- An organization `.github` repository can publish workflow templates. A template helps a repository create a workflow, but it is copied into that repository. [Workflow template documentation](https://docs.github.com/en/actions/how-tos/reuse-automations/create-workflow-templates).
- A shared reusable workflow must be called from a workflow in each consuming repository. Callers can only maintain or reduce permissions, never elevate them. [Reusable workflow documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations).
- GitHub's organization-wide code-scanning setup applies to CodeQL default setup, not arbitrary third-party SARIF producers. It can enable CodeQL default setup at scale for eligible repositories and apply a CodeQL configuration property. [Code scanning at scale](https://docs.github.com/en/enterprise-cloud@latest/code-security/how-tos/secure-at-scale/configure-organization-security/configure-specific-tools/code-scanning-at-scale).

Inference: GitHub provides no documented organization switch that installs or runs the Scorecard Action everywhere. Use an organization workflow template or a shared reusable workflow to reduce duplication, then add a small caller workflow in each repository. Use organization Actions policy to require SHA pins and allow the required canonical actions. The GitHub documentation supports the mechanisms; the statement that they do not auto-install Scorecard follows from their per-repository template and caller model.

### Repository eligibility and exceptions

Facts:

- The Action supports public repositories for free. Private Action support needs GitHub Advanced Security. It does not support fork repositories or GitHub Enterprise repositories. `push` and `schedule` on the default branch are supported; `pull_request` and `workflow_dispatch` are experimental. [Action support and trigger statement](https://github.com/ossf/scorecard-action/blob/2d1146689b8cda280b9bc96326124645441f03bc/README.md#scorecards-github-action).
- Scorecard's `Maintained` check gives archived repositories its lowest score. That is a report about maintenance, not an Action incompatibility. [Maintained check source](https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/docs/checks.md#maintained).
- Scorecard evaluates GitHub-hosted project practices, including GitHub workflow dependencies. It is not a classifier for whether a repository contains product source code. [Scorecard checks source](https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/docs/checks.md).

Recommendations:

- Public, active repositories with source, packaging, infrastructure, or workflow code should use the standard workflow. A low score can expose a meaningful policy gap even in a configuration repository.
- Private repositories need an entitlement and permission review first. If GitHub Advanced Security is absent, use the Scorecard CLI only if its output and access model meet the repository's handling rules. Do not attempt SARIF upload as a substitute for entitlement.
- Do not add the Action to a fork. Scan the upstream repository, or run the CLI outside the fork if there is a separate reason to assess it.
- Do not add new scheduled work to archived repositories. Preserve an existing workflow only if recurring evidence has a documented consumer. Otherwise record the final score and retire the schedule. The expected `Maintained` result will remain low.
- Documentation-only, profile, or metadata repositories are technically eligible when public and non-forked, but rollout is a judgment call. Include them if they contain Actions, automation, or policy that Scorecard can assess. Exclude a repository that has no code or workflow policy with a written rationale, rather than treating an inapplicable score as a defect.

### Triggers and maintenance plan

Facts:

- Upstream's maintained workflow runs on the default-branch push and weekly schedule. GitHub's SARIF guide also gives push plus a weekly schedule as its example. [OpenSSF example](https://github.com/ossf/scorecard/blob/f92023a3f77879f96e0c9c1305f289d755be4bb6/.github/workflows/scorecard-analysis.yml), [GitHub SARIF guide](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/integrate-with-existing-tools/upload-sarif-file).
- The organization workflows additionally use `branch_protection_rule`, which is sensible because Scorecard reports branch-policy state. This trigger is an observed local choice, not a current upstream requirement.
- GitHub warns against using `pull_request_target` with untrusted code. It must not check out code from a fork or other untrusted repository. [GitHub secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use#mitigating-the-risks-of-untrusted-code-checkout).

Recommended rollout and maintenance:

1. Keep the existing six workflows. Add the standard workflow to `ci` first because it contains CI and release automation. Assess `.github` separately as a workflow-template and organization-policy repository. The decision should be based on whether it contains reusable workflow or policy code worth scoring, not its language field.
2. Use a weekly cron at a non-round UTC minute. Keep the default-branch push. Retain `branch_protection_rule` where prompt branch-policy changes matter. `workflow_dispatch` is useful for operators but is experimental upstream, so it should not be the only evidence path.
3. Do not add a `pull_request` trigger in the default template. Revisit only after the Action documents it as supported, or after a repository has a specific pre-merge reason and a test plan for same-repository and fork PRs.
4. Review Scorecard runs after initial enablement: workflow success, SARIF ingestion, public result publication, and whether findings reflect expected repository policy. A workflow run is not proof that every Scorecard check has enough GitHub API visibility.
5. Let a controlled dependency updater propose SHA and version-comment updates. Verify the proposed SHA resolves in the canonical action repository, compare upstream release notes and the maintained Scorecard example, then test one repository before applying the same update elsewhere.
6. Review the repository inventory quarterly and after creating, archiving, privatizing, or forking a repository. Record exclusions, entitlement limits, and any PAT's owner, scopes, selected repositories, expiry, and rotation date in the organization's private security record, not in this repository.

## Validation and limits

On 2026-09-14, I queried GitHub's public REST endpoints for `nix-forge` repository metadata and workflow inventories, then read the default-branch `scorecard.yml` files for repositories reporting an active OpenSSF Scorecard workflow. The inventory returned eight public, non-archived, non-forked repositories. It returned active Scorecard workflows for the six repositories named above and none for `ci` or `.github`.

The six observed workflows all pin Scorecard Action v2.4.4 at `2d1146689b8cda280b9bc96326124645441f03bc`, checkout v7.0.1 at `3d3c42e5aac5ba805825da76410c181273ba90b1`, and upload-sarif v4.38.0 at `b96794f015dfd88f77b49b1c93e0fa7110f94c63`. They use the weekly Monday `23 4 * * 1` schedule, `main` push, `branch_protection_rule`, manual dispatch, top-level `permissions: {}`, and a narrowly permissioned job. Five use `ubuntu-24.04`; `nix-seal` uses `ubuntu-latest`. This is configuration evidence only. I did not trigger workflows, inspect private repositories, inspect organization settings, or verify GitHub Advanced Security entitlement.

No source or configuration outside this new note was changed. The primary sources were retrieved on the review date and may change.

## Implication for this repository

`nix-conf` already follows the recommended public-repository pattern and is marginally newer than OpenSSF's upload-sarif reference at the time of review. Keep its SHA pins and narrow job permissions. Its `branch_protection_rule` trigger is a useful local extension. No configuration change follows from this research alone.
