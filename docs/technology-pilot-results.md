# Documentation and extension catalog pilots

Reviewed: 2026-09-10. These bounded experiments follow the
[technology review](technology-stack-research.md). They use Nixpkgs
`c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0` and the current guide and editor
configuration, including the new Oxc extension selection.

## Documentation engine decision

Keep MkDocs 1.6.1 for the current guide. Zensical 0.0.59 builds an adapted copy
with a smaller output, but a theme migration and browser validation remain
necessary before it can preserve the current guide's appearance and navigation.
No demonstrated reader benefit justifies that migration in this task.

The experiment called the existing `site/build.py` staging function, preserving
source-snippet verification and its public-file allowlist. Only the renderer
callback changed in the temporary pilot. Both engines came from the pinned
Nixpkgs above. No plugin installation, dependency update or production build
configuration changed.

The unmodified configuration was not interchangeable between engines:

- Zensical rejected staging or output paths outside its project root. Relative
  `docs` and `output` directories beside a temporary configuration resolved the
  path constraints. An intermediate absolute-path attempt also raised a Rust
  panic; that was not a successful build.
- The stock `mkdocs` theme was unavailable to Zensical. Its own `modern` theme
  built successfully with external fonts disabled.
- That first successful strict build did not preserve fenced code blocks.
  MkDocs supplies `fenced_code` and `tables` by default, while the supplied
  Zensical configuration needed them explicitly. Several shell commands became
  inline text, and the embedded Nix example was split into paragraphs. Adding
  those extensions fixed the compared code blocks.
- The existing Bootstrap stylesheet's `.navbar`, `.navbar-brand` and `.table`
  selectors matched no candidate elements. Retaining the CSS file alone does
  not preserve its navigation colors or table styling.
- Search output changed from `search/search_index.json` to `search.json`, so
  the existing Nix build's search-artifact assertion needs an intentional change.

The adapted candidate preserved the 17 HTML output paths. A parser comparison
found equal code-block text and level-one through level-three headings across
all 16 content pages, excluding the generated error page. All checked local
link targets existed. Both engines rejected an injected missing-page link and
an injected missing anchor in strict mode. These checks cover content and
validation behavior; they do not establish mobile navigation, keyboard use,
interactive search or offline browser behavior.

| Warm local build observation | MkDocs | Adapted Zensical |
| --- | --- | --- |
| Output size | 2,338,135 bytes | 959,733 bytes |
| HTML files | 17 | 17 |
| Timed local operation | 0.10 seconds | 0.36 seconds |

The timing is one warm run, not a benchmark claim. The MkDocs value includes
builder staging and its Python API call; the Zensical value measures only its
renderer subprocess, including CLI startup. No
Nix sandbox reproducibility comparison or browser performance measurement ran.

The remaining migration work is specific: port the theme styling, update the
renderer and output checks, preserve explicit Markdown extensions, and test
search and navigation in a real browser. Keep source-snippet verification and
reviewed content staging whichever engine is used. Zensical's own
[migration guide](https://zensical.org/docs/compatibility/mkdocs/migration/)
recommends comparing the existing project before switching commands. Its
[pinned Nixpkgs recipe](https://github.com/NixOS/nixpkgs/blob/c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0/pkgs/by-name/ze/zensical/package.nix)
provides a reproducible dependency source for a future trial.

## Extension catalog decision

Keep nix4vscode. The alternative resolves the complete compared set on both
platforms, but it does not fix an observed availability gap and would downgrade
the newly selected Oxc extension.

The comparison evaluated 58 distinct Marketplace identifiers from the shared
editor settings, language modules and AI module on `x86_64-linux` and
`aarch64-darwin`. It included the conditional direnv extension and
`oxc.oxc-vscode`. The directly packaged Copilot Chat extension and local theme
were outside the catalog comparison. This was a package evaluation, not a GUI
installation or a native-extension execution test.

Both catalogs used the same Nixpkgs and VS Code 1.136.1. The current catalog was
nix4vscode `838c2aa12b311adf603db4c9640cb9bd59722b71`, using its
`forVscodeVersionRaw` function with those packages and identifiers. The candidate
was nix-vscode-extensions `afb516e7ccb5c83b22711c33e49e5436dd03cadc`, using its
overlay's `forVSCodeVersion` and `vscode-marketplace-release` set. This preserves
the release-only and editor-version constraints rather than comparing against
an unconstrained latest/prerelease catalog.

| Result | Linux | Apple silicon macOS |
| --- | --- | --- |
| Identifiers resolved by each catalog | 58 of 58 | 58 of 58 |
| Same selected version | 54 | 54 |
| Candidate selects a newer version | 3 | 3 |
| Candidate selects an older version | 1 | 1 |

| Extension | Current | Candidate | Platform |
| --- | --- | --- | --- |
| `google.colab` | 0.9.3 | 0.9.4 | Both |
| `ms-vscode-remote.remote-containers` | 0.466.0 | 0.469.0 | Both |
| `myriad-dreamin.tinymist` | 0.15.4 | 0.15.6 | macOS |
| `timonwong.shellcheck` | 0.39.5 | 0.40.0 | Linux |
| `oxc.oxc-vscode` | 1.60.0 | 1.39.0 | Both |

The Oxc 1.60.0 VSIX selected by nix4vscode was downloaded and its actual
`extension/package.json` inspected. It requires VS Code `^1.93.0` and declares
both `oxc.path.oxlint` and `oxc.requireConfig`, the settings used by the new
repository integration. This verifies those settings exist in the selected
extension. It does not establish that its language server ran in VS Code.

The candidate selected platform-specific Oxc downloads, while the current
catalog selected its universal download. Version numbers alone do not establish
native compatibility. Retain the existing catalog and treat its stopped public
issue intake as an explicit maintenance tradeoff. A future migration should
compare actual native behavior and preserve required versions, rather than
accepting every changed version as an improvement.

Sources are the pinned [current selection implementation](https://github.com/nix-community/nix4vscode/blob/838c2aa12b311adf603db4c9640cb9bd59722b71/nix/forVscodeVersionRaw.nix),
[candidate overlay](https://github.com/nix-community/nix-vscode-extensions/blob/afb516e7ccb5c83b22711c33e49e5436dd03cadc/nix/overlay.nix),
[candidate catalog](https://github.com/nix-community/nix-vscode-extensions/blob/afb516e7ccb5c83b22711c33e49e5436dd03cadc/data/cache/vscode-marketplace-latest.json),
and [nix4vscode support policy](https://github.com/nix-community/nix4vscode).

## Validation and limits

Package evaluations ran through the desktop workload runner. No production
input changed and no extension was installed or activated. Evaluation proves
the declared derivations resolve; it does not prove all VSIX downloads build,
native components work, or extension functionality is unchanged.
