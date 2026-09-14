# Public guide implementation research

Reviewed: 2026-09-10. Scope: public documentation, portable examples, and GitHub
contribution tooling. Repository base: `7fd38c80a2aabdb16674fba7231496fa4a575bee`.

## Answer

Use MkDocs from the existing pinned Nixpkgs input. Keep source Markdown where
GitHub readers already find it and stage the public site during the Nix build.
Give the introductory guides a short navigation menu and make reference material
searchable. Link readers to small, independently buildable examples. Build those
examples in CI and run the NixOS example in the existing VM test infrastructure.

This recommendation follows the repository's large existing Markdown collection.
It does not require replacing that material with a second documentation tree.

## Findings and sources

### Documentation engine

Local evaluation found MkDocs 1.6.1 and mdBook 0.5.4 in Nixpkgs revision
`c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0`. Both have pinned source hashes and build
dependencies, so either can run without installing an unrelated language toolchain
through a network package manager during the site build.
[MkDocs package](https://github.com/NixOS/nixpkgs/blob/c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0/pkgs/development/python-modules/mkdocs/default.nix),
[mdBook package](https://github.com/NixOS/nixpkgs/blob/c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0/pkgs/by-name/md/mdbook/package.nix).

MkDocs supports a chosen navigation tree while building other Markdown pages.
It includes search, configurable validation, and a project URL with a subdirectory.
`use_directory_urls: false` makes the rendered HTML easier to inspect through a
local static server. Set the correct `/nix-conf/` canonical base, explicit source
links, missing-link warnings, and strict builds. Search prebuilding adds a Node
dependency; leave that optional feature off initially. An optional local hook can
adapt source links during site generation without changing GitHub Markdown.
[Configuration](https://www.mkdocs.org/user-guide/configuration/).

Keep normal `.md` links between chapters. MkDocs resolves them into generated
page URLs. Use copied reviewed assets, descriptive alternative text, and small
complete fenced examples that remain readable on GitHub.
[Writing documentation](https://www.mkdocs.org/user-guide/writing-your-docs/).

mdBook includes search and file inclusion. It uses `SUMMARY.md` to define chapters
and a built-in preprocessor maps chapter `README.md` files to indexes. It is a good
fit for a book authored as a chapter sequence. Here its explicit chapter inventory
would add work to accommodate the existing reference collection. Include directives
also do not render as examples on GitHub. This is an implementation tradeoff, not
a quality judgment about either generator.
[General configuration](https://rust-lang.github.io/mdBook/format/configuration/general.html),
[Preprocessors](https://rust-lang.github.io/mdBook/format/configuration/preprocessors.html),
[HTML renderer](https://rust-lang.github.io/mdBook/format/configuration/renderers.html).

Implementation choice: stage only reviewed public Markdown and its assets. Preserve
the repository-relative paths inside that staging tree. Convert links to source
files outside the documentation into GitHub links, preserving fragments. Do not
copy the whole checkout into the published artifact. Rendered-page link checks
should cover nested paths, source links, asset links, and anchors. Do not globally
suppress broken-link warnings to accommodate legacy documents.

### Existing related-project pattern

The local vpn-confinement checkout uses Astro/Starlight through Bun. Its
`site/scripts/sync-root-docs.ts` copies authoritative root contribution and security
documents into generated site files. Its `flake/docs.nix` generates an option
reference with `nixosOptionsDoc`. Its docs workflow builds pull requests, then
publishes only a main-branch push using a separate deployment job.

Reuse its authoritative-source approach and separation of build from deployment.
Its Bun/Astro stack is already justified for that site; introducing the same stack
into nix-conf would create another dependency lock and frontend build without a
requirement that needs it. Inspection covered source files only, not an execution
of the related project's site build.
[Repository](https://github.com/nix-forge/vpn-confinement).

### GitHub Pages and contribution forms

Build and validate the site on pull requests. Upload and deploy only trusted
main-branch pushes, with read-only permissions in the build job. Deployment needs
`pages: write`, `id-token: write`, a dependency on the build job, and a `github-pages`
environment. The Pages publishing source must be configured for GitHub Actions.
Pages artifacts must not contain symbolic or hard links, so materialize the Nix
output when preparing the upload directory.
[GitHub custom Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

Use full commit pins for external actions, matching the repository's existing
workflow convention.
[GitHub secure use reference](https://docs.github.com/en/actions/reference/security/secure-use).

Remote tag lookup verified these action revisions during this investigation:

| Action | Version | Commit |
| --- | --- | --- |
| `actions/configure-pages` | `v5` | `983d7736d9b0ae728b81ab479565c72886d7745b` |
| `actions/upload-pages-artifact` | `v5.0.0` | `fc324d3547104276b827a68afc52ff2a11cc49c9` |
| `actions/deploy-pages` | `v5.0.1` | `368f82528645a54fb793d4d04e342629a3f51346` |

GitHub issue forms support required inputs and structured dropdowns. Add a small
bug form and guide-feedback form asking for the revision, platform, reproduction,
expected result, and observed result. Avoid requiring full configuration or raw
logs. A focused redacted excerpt is usually sufficient. Link security reporting
through the existing policy rather than inviting reports in public issues.
[Issue form syntax](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms).

### Teaching examples and honest checks

Home Manager supports standalone flake configurations and separate build/activation
operations. Match the Home Manager and Nixpkgs release tracks, commit each starter
lock, and require the reader to set their own username and home directory before
activation.
[Standalone flakes](https://nix-community.github.io/home-manager/nix-flakes/standalone.html),
[Release compatibility option](https://nix-community.github.io/home-manager/options/home-manager/home.html).

`DRY_RUN=1` asks activation blocks to report their actions. The activation script
also supports a driver version argument; version 1 leaves profile management to
its caller. Local source inspection found that activation initialization runs a
Nix sanity check, profile query, and profile setup before dry-run handling. A
dry-run therefore must not be described as producing no filesystem writes or as
working inside a Nix builder without a daemon. Build the activation package and
assert observable generated files in ordinary checks. Test actual activation in
a neutral test home or VM, and call out any runtime checks that have not run.
[Activation internals](https://nix-community.github.io/home-manager/internals/activation.html),
[Activation block contract](https://nix-community.github.io/home-manager/options/home-manager/home.html).

The NixOS VM teaching example should import a neutral public configuration, expose
an explicit VM build/run output, and document the test account and how to discard
the test disk. A VM is a suitable first system experiment because the reader can
inspect the resulting configuration before installing a workstation.
[NixOS VM tutorial](https://nix.dev/tutorials/nixos/nixos-configuration-on-vm.html).

Use `pkgs.testers.runNixOSTest` to boot the same module the guide explains. Wait for
the relevant unit, then assert the observable service or file behavior. A boot
test gives evidence that evaluation alone cannot provide. Keep Linux VM checks
separate from Darwin evaluation and native Home Manager builds.
[NixOS integration testing tutorial](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html).

## Validation and limits

Ran local flake evaluation to obtain dependency versions and source paths. Read
the pinned Nixpkgs package recipes and Home Manager activation implementation.
Inspected the related project's docs build, source synchronization, and deployment
workflow. Verified the three Pages action refs with `git ls-remote`.

No documentation build, Home Manager activation, VM runtime test, or deployment
ran as part of this read-only research assignment. Those checks belong to the
implementation owners. The current primary documentation was retrieved on the
review date; implementation should follow the pinned versions when behavior
differs.

## Implication for this repository

Implement the docs package as a small Nix build with pinned MkDocs and a narrowly
scoped staging step. Keep public examples independent of personal host imports.
Register docs validation and example checks with the current CI inventory, and
add the Pages workflow after the local site builds cleanly. Prepare release and
launch text locally; neither independent reader testing nor public announcement
has happened yet.
