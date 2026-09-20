# OpenSSF Developer Best Practices, metal-series research and implementation

Reviewed: 2026-09-15 UTC. Scope: the OpenSSF Best Practices Badge Program's
metal series, specifically the `passing` level, and the public GitHub state of
the nix-forge repositories named below. This is a research and implementation
record, not an independent OpenSSF audit.

## Answer

The current program has two separate series: OpenSSF Baseline and the older,
broader metal series. This note covers the metal series: `passing`, `silver`,
and `gold`. The passing assessments described below were completed for all
eight repositories. A passing badge requires every active passing-level question to be
"enough". That means a MUST is `Met`, or permitted `N/A` with any required
justification; a SHOULD is `Met` or `Unmet` with a non-placeholder
justification of at least five characters; and a SUGGESTED may be `Met` or
`Unmet`. Required URLs and justifications still have to be supplied. The
application computes a percentage across all active questions, and passing is
100 percent. [The criterion data][criteria] and [evaluation code][project-model]
are the authority.

The source snapshot was commit
[`b053147e23850eeee67c131ae9b228c41447fc6b`][source-commit], committed
2026-09-14T19:21:36-04:00, which is 2026-09-15 UTC. The requested date is
therefore a UTC snapshot, not a prediction of later changes on that date.

## Passing criteria

There are 67 active passing questions: 43 MUST, 10 SHOULD, and 14 SUGGESTED.
The exact question identifiers below are intentionally included, since they
are the stable field names in BadgeApp. Read their full normative text,
clarifications, allowed `N/A` cases, and evidence-field requirements in the
[current criterion data][criteria] or [passing page][passing-page].

| Area | MUST | SHOULD | SUGGESTED |
| --- | --- | --- | --- |
| Basics | `description_good`, `interact`, `contribution`, `floss_license`, `license_location`, `documentation_basics`, `documentation_interface`, `sites_https`, `discussion`, `maintained` | `contribution_requirements`, `english` | `floss_license_osi` |
| Change control | `repo_public`, `repo_track`, `repo_interim`, `version_unique`, `release_notes`, `release_notes_vulns` | `report_tracker`, `enhancement_responses` | `repo_distributed`, `version_semver`, `version_tags` |
| Reporting | `report_process`, `report_responses`, `report_archive`, `vulnerability_report_process`, `vulnerability_report_private`, `vulnerability_report_response` | none | none |
| Quality | `build`, `test`, `test_policy`, `tests_are_added`, `warnings`, `warnings_fixed` | `build_floss_tools`, `test_invocation` | `build_common_tools`, `test_most`, `test_continuous_integration`, `tests_documented_added`, `warnings_strict` |
| Security knowledge and cryptography | `know_secure_design`, `know_common_errors`, `crypto_published`, `crypto_floss`, `crypto_keylength`, `crypto_working`, `crypto_password_storage`, `crypto_random` | `crypto_call`, `crypto_weaknesses`, `crypto_pfs` | none |
| Delivery and vulnerability handling | `delivery_mitm`, `delivery_unsigned`, `vulnerabilities_fixed_60_days`, `no_leaked_credentials`, `static_analysis`, `static_analysis_fixed`, `dynamic_analysis_fixed` | `vulnerabilities_critical_fixed` | `static_analysis_common_vulnerabilities`, `static_analysis_often`, `dynamic_analysis`, `dynamic_analysis_unsafe`, `dynamic_analysis_enable_assertions` |

In plain terms, passing covers an understandable, maintained public project;
FLOSS licensing and HTTPS; public revision history and release information;
public and private reporting paths; a working build, tests, warnings, and
static analysis; secure-development knowledge; sound use of cryptography when
applicable; secure delivery; credential protection; and timely vulnerability
handling. The table is the exact checklist. The prose is only a guide.

## How status and higher levels work

### Documented facts

- `badge_percentage_0` is the percentage of active passing questions that are
  enough. `badge_level` is `in_progress` below 100, then `passing`, `silver`,
  or `gold` from integer division of the tiered percentage. [Project model][project-model]
- Tiered progress deliberately hides higher-level progress until the prior
  level reaches 100: passing progress is 0-99; after passing, silver progress
  is reported as 100-199; after silver, gold progress is 200-300. [API
  documentation][api-docs] and [implementation][project-model]
- Silver contains 55 active questions: 44 MUST, 10 SHOULD, one SUGGESTED. Its
  `achieve_passing` MUST makes passing a prerequisite. It adds governance,
  continuity, current/security/quick-start documentation, coding standards,
  dependency monitoring, 80% statement coverage, signed releases, input
  validation, an assurance case, and many stricter versions of passing
  questions. [Silver criteria][all-criteria]
- Gold contains 22 active questions: 20 MUST and two SHOULD. Its
  `achieve_silver` MUST makes silver a prerequisite. It adds an unassociated
  contributor requirement, per-file copyright and licence information, 2FA,
  review rules and 50% two-person review, reproducible builds, CI, 90%
  statement and 80% branch coverage, secure network defaults and TLS 1.2,
  hardening, and security review. [Gold criteria][all-criteria]

### Inference

The metal badge is primarily a project-owner self-certification backed by
public justifications, not an independent continuous audit. This follows from
the per-project statuses and justifications exposed by the API and the program
source that recomputes a score from them. A reviewer should verify linked
evidence before relying on a badge.

## Public repository audit

I queried the BadgeApp project API and GitHub's public repository metadata and
default-branch trees on 2026-09-15 UTC. GitHub identifies all eight targets as
public, non-archived repositories. GitHub's documented community-health file
locations explain why root and `.github/` files are relevant evidence. [GitHub
documentation][github-health]

| Repository | BadgeApp record | Public evidence found | Audit result |
| --- | --- | --- | --- |
| [`.github`](https://github.com/nix-forge/.github) | [14648](https://www.bestpractices.dev/projects/14648), passing 100% | README, MIT licence, CONTRIBUTING, SECURITY, GOVERNANCE, DCO, CODE_OF_CONDUCT, SUPPORT, issue templates, CI, CodeQL, Dependabot | Passing earned; support-only build and cryptography criteria use scoped N/A justifications. |
| [`ci`](https://github.com/nix-forge/ci) | [14642](https://www.bestpractices.dev/projects/14642), passing 100% | Same community documents; CI, CodeQL, DCO, dependency review, release, and workflow files; architecture and release docs | Passing earned with evidence links for all 67 criteria. |
| [`nix-conf`](https://github.com/nix-forge/nix-conf) | [14637](https://www.bestpractices.dev/projects/14637), passing 100% | Same community documents; CI, CodeQL, DCO, dependency review, scorecard; testing and architecture docs | Passing earned with evidence links for all 67 criteria. |
| [`nix-homelab`](https://github.com/nix-forge/nix-homelab) | [14638](https://www.bestpractices.dev/projects/14638), passing 100% | Same community documents; CI, CodeQL, DCO, dependency review, scorecard; changelog, roadmap, test docs | Passing earned with evidence links for all 67 criteria. |
| [`nixpkgs-personal`](https://github.com/nix-forge/nixpkgs-personal) | [14639](https://www.bestpractices.dev/projects/14639), passing 100% | Same community documents; CI, CodeQL, DCO, dependency review, scorecard, package update workflow | Passing earned; Swift sanitizer jobs provide additional dynamic-analysis evidence. |
| [`nix-seal`](https://github.com/nix-forge/nix-seal) | [14636](https://www.bestpractices.dev/projects/14636), passing 100% | Same community documents; CI, CodeQL, DCO, dependency review, releases, scorecard, assurance workflow, roadmap | Passing earned; age cryptography, fuzz smoke tests, Miri, and address-sanitizer evidence were recorded explicitly. |
| [`nix-config-framework`](https://github.com/nix-forge/nix-config-framework) | [14641](https://www.bestpractices.dev/projects/14641), passing 100% | Same community documents; CI, CodeQL, DCO, dependency review, releases, scorecard, example docs | Passing earned with evidence links for all 67 criteria. |
| [`vpn-confinement`](https://github.com/nix-forge/vpn-confinement) | [14640](https://www.bestpractices.dev/projects/14640), passing 100% | Same community documents; CI, CodeQL, DCO, dependency review, scorecard, architecture and security docs | Passing earned; WireGuard cryptography and tunnel security evidence were recorded explicitly. |

The shared documents and workflows are public evidence for many questions. The
BadgeApp entries now contain the project-specific status and justification for
each question; repository settings were also verified separately, including
protected main branches, organization-wide 2FA, secret scanning, and private
vulnerability reporting.

## Unresolved gaps

- The metal series is self-attested: a passing result should still be reviewed
  against the linked repository evidence before it is treated as an audit.
- Passing allows scoped N/A answers and non-blocking unmet SUGGESTED criteria.
  The current entries intentionally do not claim a published statement-coverage
  percentage for repositories without one, and do not claim SemVer tags where no
  release tag stream exists.
- Silver and gold need their own answers after the prerequisite level passes.
  The public files alone cannot prove their coverage, review-rate, continuity,
  access, or security-review requirements.
- The README badge-link PRs are documentation-only and remain subject to the
  repositories' required second-person review rule; the public BadgeApp result
  itself is already passing.

## Validation and limits

I used BadgeApp's public project API for the eight repository URLs and its
authenticated browser form to record all 67 passing criteria per project. The
final public API verification reported `badge_level: passing`,
`badge_percentage_0: 100`, and `achieve_passing_status: Met` for IDs 14636,
14637, 14638, 14639, 14640, 14641, 14642, and 14648. GitHub REST checks also
verified the organization 2FA policy, Pages HTTPS, private vulnerability
reporting, community health, security settings, and protected main branches.

[criteria]: https://github.com/ossf/best-practices-badge/blob/b053147e23850eeee67c131ae9b228c41447fc6b/criteria/criteria.yml
[project-model]: https://github.com/ossf/best-practices-badge/blob/b053147e23850eeee67c131ae9b228c41447fc6b/app/models/project.rb
[source-commit]: https://github.com/ossf/best-practices-badge/commit/b053147e23850eeee67c131ae9b228c41447fc6b
[passing-page]: https://www.bestpractices.dev/criteria/0?details=true
[all-criteria]: https://www.bestpractices.dev/criteria?details=true
[api-docs]: https://github.com/ossf/best-practices-badge/blob/b053147e23850eeee67c131ae9b228c41447fc6b/docs/api.md
[github-health]: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/adding-a-code-of-conduct-to-your-project

## Silver reassessment, 2026-09-15 UTC

### Answer

No, none of the eight repositories can honestly claim the metal-series Silver
badge today. This is not a close paperwork exercise. Each has a passing badge,
but its public BadgeApp entry reports only 15% Silver progress and leaves 47 of
the 55 Silver answers unset. The eight "enough" answers are the passing
prerequisite, contribution requirements, issue tracker, documented test-addition
policy, strict warnings, static analysis for common vulnerabilities, and two
criterion-specific crypto or memory-safety answers. The exact pair varies by
repository. BadgeApp counts `Met` and permitted `N/A` as enough, so eight of 55
rounds to 15%.[^silver-api]

Silver is achievable over time, but it needs an evidence programme, not merely
a set of policy files. In particular, every project needs credible evidence for
the 80% statement-coverage and 50%-of-fixed-bugs regression-test requirements,
and a second person with enough authority to keep the project operating after
one maintainer is gone. The latter is an access and governance change, not
something a repository author can establish alone. `contributors_unassociated`
is *not* a Silver requirement. It begins at Gold, so lack of an outside
contributor is not a Silver blocker.[^silver-source]

### Exact Silver checklist

The identifiers and categories below are the complete active Silver checklist
at source commit [`b053147e23850eeee67c131ae9b228c41447fc6b`][source-commit],
retrieved on 2026-09-15 UTC. The linked English criterion text is normative,
including its N/A cases and evidence requirements.[^silver-source]

| Area | MUST | SHOULD | SUGGESTED |
| --- | --- | --- | --- |
| Prerequisite and oversight | `achieve_passing`, `contribution_requirements`, `governance`, `code_of_conduct`, `roles_responsibilities`, `access_continuity` | `dco`, `bus_factor` | none |
| Documentation and maintenance | `documentation_roadmap`, `documentation_architecture`, `documentation_security`, `documentation_quick_start`, `documentation_current`, `documentation_achievements`, `sites_password_security`, `maintenance_or_update` | `accessibility_best_practices`, `internationalization` | none |
| Reporting and quality | `report_tracker`, `vulnerability_report_credit`, `vulnerability_response_process`, `coding_standards`, `coding_standards_enforced`, `build_standard_variables`, `build_non_recursive`, `build_repeatable`, `installation_common`, `installation_standard_variables`, `installation_development_quick`, `external_dependencies`, `dependency_monitoring`, `updateable_reused_components`, `automated_integration_testing`, `regression_tests_added50`, `test_statement_coverage80`, `test_policy_mandated`, `tests_documented_added`, `warnings_strict` | `build_preserve_debug`, `interfaces_current` | none |
| Security and analysis | `implement_secure_design`, `crypto_weaknesses`, `crypto_credential_agility`, `crypto_certificate_verification`, `crypto_verification_private`, `signed_releases`, `input_validation`, `assurance_case`, `static_analysis_common_vulnerabilities`, `dynamic_analysis_unsafe` | `crypto_algorithm_agility`, `crypto_used_network`, `crypto_tls12`, `hardening` | `version_tags_signed` |

This is 44 MUSTs, 10 recommended criteria, and one SUGGESTED criterion. The category matters:
all active MUSTs must be `Met` or allowed `N/A`; recommended criteria may be `Unmet` with a
real justification; the SUGGESTED answer may be `Met` or `Unmet`.[^silver-source]

### Public-state map

I queried each BadgeApp project JSON record and GitHub's public repository,
tree, releases, contributor, and label endpoints at 2026-09-15T06:38Z. GitHub
reports all eight repositories public, non-archived, on `main`. The result is
an evidence inventory, not proof that a workflow ran successfully or that a
private GitHub permission is correctly assigned.[^github-api]

| Repository | Current BadgeApp Silver evidence | Public candidates for the unset answers | Material gap or external dependency |
| --- | --- | --- | --- |
| [`ci`](https://github.com/nix-forge/ci) | 15%; `crypto_weaknesses` and `dynamic_analysis_unsafe` are N/A | Governance, contribution and security files; architecture and release docs; CI, CodeQL, DCO, dependency-review, release, and Scorecard workflows | Only one public contributor appears in the API. No coverage report or six-month regression-test sample was found. A release exists, but public signed-tag/key verification still needs evidence. |
| [`nix-conf`](https://github.com/nix-forge/nix-conf) | 15%; the same two scoped N/A answers | Community files, architecture and testing docs, flake/Just build entry points, CI, CodeQL, dependency review, and Scorecard | No roadmap or coverage artifact found. The public tree includes C/C++ test helpers, so the N/A rationale for `dynamic_analysis_unsafe` needs scope proof or sanitizer/fuzzer evidence. |
| [`nix-homelab`](https://github.com/nix-forge/nix-homelab) | 15%; the same two scoped N/A answers | `docs/roadmap.md`, testing and release docs, Nix integration tests, and CI/security workflows | No architecture or coverage artifact found. Its April 2026 creation leaves a short history for the six-month regression-test claim. |
| [`nixpkgs-personal`](https://github.com/nix-forge/nixpkgs-personal) | 15%; `dynamic_analysis_unsafe` is `Met`, `crypto_weaknesses` N/A | Package manifests, package tests, CI, CodeQL, dependency review, and update workflow | The `Met` answer needs a linked routine dynamic-analysis result. Coverage and regression-test history are absent. It was created in July 2026. |
| [`nix-seal`](https://github.com/nix-forge/nix-seal) | 15%; both `crypto_weaknesses` and `dynamic_analysis_unsafe` are `Met` | Rust crates, fuzz directory, assurance and release workflows, roadmap, threat model, CI and CodeQL | This is the strongest technical starting point, but neither a published coverage result nor the required regression-test sample is public. Release signatures, public verification keys, and the assurance-case argument still need explicit evidence. |
| [`nix-config-framework`](https://github.com/nix-forge/nix-config-framework) | 15%; the same two scoped N/A answers | Integration and policy tests, release docs, CI, CodeQL, dependency review, and Scorecard | No roadmap, architecture document, coverage report, or regression-test sample found. It was created in July 2026. |
| [`vpn-confinement`](https://github.com/nix-forge/vpn-confinement) | 15%; `crypto_weaknesses` is `Met`, `dynamic_analysis_unsafe` N/A | Architecture and security site docs, threat model, Nix evaluation/runtime tests, CI and CodeQL | Network and WireGuard claims need complete evidence for credential agility, secure protocol defaults, TLS N/A cases, certificate verification, and input validation. No roadmap, coverage artifact, or regression-test sample was found. |
| [`.github`](https://github.com/nix-forge/.github) | 15%; the same two scoped N/A answers | Organization governance, health files, workflow templates, CI, CodeQL, and Scorecard | This support repository can likely use N/A for software-only criteria, but it still needs a documented one-year roadmap, access-continuity evidence, and a completed Silver form. One public contributor is visible. |

All eight repositories expose `good first issue` labels, which is useful for
future onboarding but does not satisfy any Silver criterion by itself. GitHub's
contributors endpoint lists one non-bot public handle for every repository,
with bots also listed on some repositories. That is insufficient public evidence
for a bus factor of two and actively contradicts a claim that a second proven
maintainer is already visible. It does not, by itself, prove the private access
state or rule out a qualified maintainer whose work is not visible in that
endpoint.[^github-api]

### What can be fixed in a repository, and what cannot

| Kind | Silver criteria | What is needed |
| --- | --- | --- |
| Repository work | Documentation, coding, dependency, build, installation, security, and analysis criteria that remain unset | Complete the Silver questionnaire with durable links. Add or tighten the missing roadmap, architecture, quick-start, current-documentation, achievement, coding-standard, dependency, input-validation, assurance-case, and release-verification evidence where it is genuinely true. Use scoped N/A only where the criterion permits it. |
| Measured or historical evidence | `regression_tests_added50`, `test_statement_coverage80`, `documentation_current`, `maintenance_or_update`, `vulnerability_report_credit`, `automated_integration_testing`, `build_repeatable`, `signed_releases`, and routine dynamic analysis where applicable | Publish reproducible coverage output at or above 80%, retain a six-month bug-fix and regression-test sample, preserve CI/build/release artifacts, and document how signatures and keys are verified. A policy promising these things does not prove them. |
| Another maintainer or GitHub administration | `access_continuity`, and the `bus_factor` SHOULD | Give at least one additional trusted maintainer the practical ability to administer issues, merge changes, and release within a week. Record a tested continuity process without publishing credentials or recovery material. The current public governance text names one organization owner, so it is evidence of the gap, not evidence that the criterion is met. |
| Not a Silver blocker | `contributors_unassociated`, per-file copyright/license, 2FA, two-person review, reproducible build, 90% statement coverage, and 80% branch coverage | These are Gold criteria. They may be worthwhile preparation, but they should not delay an honest Silver assessment. |

### Recommendation

Do not submit Silver self-attestations for any of the eight yet. First establish
shared evidence conventions in `.github`, then add repository-specific
roadmaps, architecture or N/A rationales, assurance cases, coverage artifacts,
and release evidence. In parallel, the organization owner must arrange and test
continuity with another maintainer. After at least six months of tracked bug
fixes and regression tests, review the evidence per repository and fill the
Silver forms. Start with `nix-seal`, then `vpn-confinement` and `ci`; their
public security and release material gives them the least ground to make up.

### Validation and limits

This update used read-only public endpoints. It did not run repository tests,
inspect private settings, alter BadgeApp answers, or infer that a workflow file
means its jobs passed. The BadgeApp source defines scoring, but BadgeApp entries
remain project-maintainer self-attestations. GitHub contributor results omit
private activity and do not establish employment association or access rights.
The source and live APIs were retrieved on the stated UTC date; the conclusion
should be revisited when the questionnaire or public evidence changes.

[^silver-api]: [BadgeApp API documentation](https://github.com/ossf/best-practices-badge/blob/b053147e23850eeee67c131ae9b228c41447fc6b/docs/api.md) and public records for [`ci`](https://www.bestpractices.dev/projects/14642.json), [`nix-conf`](https://www.bestpractices.dev/projects/14637.json), [`nix-homelab`](https://www.bestpractices.dev/projects/14638.json), [`nixpkgs-personal`](https://www.bestpractices.dev/projects/14639.json), [`nix-seal`](https://www.bestpractices.dev/projects/14636.json), [`nix-config-framework`](https://www.bestpractices.dev/projects/14641.json), [`vpn-confinement`](https://www.bestpractices.dev/projects/14640.json), and [`.github`](https://www.bestpractices.dev/projects/14648.json), retrieved 2026-09-15 UTC.
[^silver-source]: [BadgeApp criterion categories](https://github.com/ossf/best-practices-badge/blob/b053147e23850eeee67c131ae9b228c41447fc6b/criteria/criteria.yml), [English normative criterion text](https://github.com/ossf/best-practices-badge/blob/b053147e23850eeee67c131ae9b228c41447fc6b/config/locales/en.yml), and [score implementation](https://github.com/ossf/best-practices-badge/blob/b053147e23850eeee67c131ae9b228c41447fc6b/app/models/project.rb), retrieved 2026-09-15 UTC.
[^github-api]: GitHub REST API observations from the documented [repository](https://docs.github.com/en/rest/repos/repos#get-a-repository), [tree](https://docs.github.com/en/rest/git/trees#get-a-tree), [release](https://docs.github.com/en/rest/releases/releases#list-releases), [contributor](https://docs.github.com/en/rest/repos/repos#list-repository-contributors), and [label](https://docs.github.com/en/rest/issues/labels#list-labels-for-a-repository) endpoints, retrieved 2026-09-15T06:38Z. GitHub documents the organization-wide fallback locations for community health files in [default community health files](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file).
