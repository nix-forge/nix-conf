# Documentation site tooling for nix-forge

Reviewed: 2026-09-13. Scope: the eight public repositories in the nix-forge
GitHub organization and their current documentation builds.

## Answer

Use plain MkDocs as the default documentation engine for Markdown-first
nix-forge repositories. Pin it through each repository's Nixpkgs input and
publish the resulting Nix package through GitHub Pages. Keep documentation in
the repository that owns the interface. Do not assemble a central site by
copying documents from independently released repositories.

This is a deliberately conservative choice. Material for MkDocs has a richer
theme, but its maintainers announced that critical and security fixes end on
2026-11-05. Its successor, Zensical, still describes itself as alpha software.
Starting a new migration to either one in September 2026 would trade a working
Markdown toolchain for another migration within months. See the
[Material maintenance announcement](https://github.com/squidfunk/mkdocs-material/issues/8523)
and the [Zensical roadmap](https://zensical.org/about/roadmap/).

Keep the existing Starlight site in `vpn-confinement`. It already has an active
lockfile, tailored MDX pages, a generated option reference, and a deployed site.
Replacing it would remove working design and accessibility features without
reducing current maintenance enough to justify the migration. This is an
exception based on an existing implementation, not the template for small sites.

Not every repository needs a Pages site. The special `.github` repository owns
the organization profile and workflow templates, so GitHub is its publishing
interface. Product and shared-tool repositories benefit from searchable sites:
`nix-conf`, `nixpkgs-personal`, `nix-config-framework`, `nix-seal`,
`nix-homelab`, `vpn-confinement`, and `ci`.

## Findings and sources

### Tool comparison

Versions below are upstream observations retrieved on 2026-09-13. Repository
lockfiles remain the authority for builds.

| Tool | Useful properties | Decision |
| --- | --- | --- |
| MkDocs 1.6.1 | Ordinary Markdown, explicit YAML navigation, built-in local search, configurable link and navigation validation, and static output. The [configuration reference](https://www.mkdocs.org/user-guide/configuration/) documents `strict`, `validation`, themes, hooks, and search. | Default. Its Python closure is available from pinned Nixpkgs, and a site needs no frontend package manager. |
| Material for MkDocs 9.7.7 | Mature navigation, search, and theme features. Its maintainers put the project in final maintenance and set 2026-11-05 as its end-of-life date. | Reject for new sites. Existing users can plan a separate migration. |
| Zensical | The Material team's Rust-based successor supports much of the Material configuration model. Its roadmap says it is alpha and still expanding MkDocs compatibility and plugin coverage. | Revisit after a stable release and a Nix packaging trial. |
| Starlight | Astro documentation framework with Markdown and MDX content, documentation navigation, and built-in Pagefind search. See the [Starlight documentation](https://starlight.astro.build/) and [search guide](https://starlight.astro.build/guides/site-search/). | Keep the existing `vpn-confinement` adapter. Use for a new site only when custom pages or interactive content justify Node, Astro, and lockfile maintenance. |
| VitePress 1.6 | Markdown with optional Vue content, local search, and static deployment. Project sites must set the correct GitHub Pages base path. See the [VitePress overview](https://vitepress.dev/guide/what-is-vitepress), [search reference](https://vitepress.dev/reference/default-theme-search), and [deployment guide](https://vitepress.dev/guide/deploy). | Viable, but it adds Vue and Vite without meeting a current requirement that MkDocs misses. |
| Docusaurus 3 | React and MDX documentation with built-in versioning, internationalization, broken-link policy, and static deployment. See the [documentation](https://docusaurus.io/docs), [versioning guide](https://docusaurus.io/docs/versioning), and [deployment guide](https://docusaurus.io/docs/deployment). | Use only if a project must publish several supported documentation versions. No current nix-forge repository has that requirement. |
| mdBook 0.5 | Rust book generator with a `SUMMARY.md`, keyboard navigation, search, and static output. Its [guide](https://rust-lang.github.io/mdBook/) treats content as a book and recommends a separate link checker in CI. | Good for a linear book, but the manual summary and book structure add work for the current cross-linked guides and generated Nix references. |

The generator does not prove that a site is accessible. Custom content and CSS
can break otherwise sound defaults. Release checks should cover keyboard
navigation, visible focus, heading order, landmarks, contrast, mobile reflow,
and a screen-reader smoke test.

### Repository design

The common interface is a flake package containing a complete static site. A
Pages workflow only builds, materializes, uploads, and deploys that package.
Callers do not need to know how the site stages Markdown or generates references.
This keeps the module deep: the flake package hides the generator and staging
details behind one build target.

The content and build stay local to each repository for three reasons:

- A documentation change can ship with the code and release it describes.
- Pull requests validate links and generated references against the same source
  revision.
- A repository can retain a justified adapter, such as Starlight, without making
  every other repository inherit its dependency graph.

GitHub's [custom Pages workflow guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
separates artifact upload from deployment and grants `pages: write` and
`id-token: write` only to the deployment job. The nix-forge workflows follow
that split and pin every third-party action to a commit.

For Nix modules, generate option types, defaults, descriptions, and declarations
from evaluation instead of copying them into prose. Nixpkgs documents
[`nixosOptionsDoc`](https://nixos.org/manual/nixpkgs/stable/#sec-lib-nixosOptionsDoc)
for this purpose. A generated default records the module declaration. It does
not prove that a host enables the option or that the behavior passed a runtime
test.

MkDocs checks site-local pages and anchors during the hermetic Nix build.
External HTTP checks are network-dependent and do not belong in that derivation.
Run them on a schedule with retries and a small redirect allowlist. The
[Lychee project](https://github.com/lycheeverse/lychee) supports local and online
link checking when a repository adds that separate policy.

### Published content

The root `nix-conf` site remains a curated guide. It does not publish the full
research tree, workstation operations, raw captures, or private integration
details. Package and framework sites publish stable entry points and selected
reference material. `nix-seal` publishes setup and operator guidance while the
normative specification, threat model, security policy, and ADR history remain
prominent source links. The `ci` site documents supported workflow contracts,
not the implementation of every action.

This split is more useful than turning every Markdown file into navigation.
Search may index supplementary public pages, but the main navigation follows the
reader's task: start, configure, operate, then maintain.

## Validation and limits

The inventory used the GitHub API to list all eight public organization
repositories and inspected the available local checkouts at their current
revisions. Primary-source research covered official project documentation,
release records, repositories, and GitHub Pages documentation.

The implementation evaluation checks the flake output on x86 Linux. Full static
site builds run through the desktop workload queue. No Pages deployment or
repository setting change is part of this work. Browser accessibility tests and
scheduled external-link checks remain separate follow-up work; the presence of a
framework or workflow is not evidence that those checks passed.

## Implication for this repository

Keep the curated `nix-conf` renderer and its generated feature and option
references. The root repository cannot use the common `documentation-site`
package name because it also re-exports the package collection, which owns an
output with that name. Its existing `documentation` package is the adapter at
the same publishing seam.

Use the related-project page and organization profile as the directory for the
separate sites. Keep source links on GitHub so research, code, release history,
and review context retain their repository ownership.
