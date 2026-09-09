# Which filenames give nix-seal templates the best tooling support?

Reviewed: 2026-09-08. Scope: nix-seal template naming; upstream documentation
retrieved on this date and local Linux probes with Neovim 0.12.5, Prettier 3.9.6,
and Taplo 0.10.0. Mutable upstream links describe the retrieved source.

## Answer

Recommend native filenames inside a clearly named `templates/` directory, such
as `templates/app.toml` and `templates/credentials.json`. When the basename must
identify a template independently of its directory, use `app.template.toml`.
Keeping the language extension last gives the strongest automatic detection in
the tools examined. This is a recommendation inferred from the evidence below,
not a universal template standard.

`app.toml.template` communicates intent but needs additional tool configuration.
Changing it to `.tmpl`, `.tpl`, or `.j2` does not provide a general improvement.
`.in` has a useful Neovim convention but does not solve detection across tools.
Preserve existing `.template` sources and arbitrary explicit source paths.

An extension only helps tools identify the language. It cannot make a template
with arbitrary placeholders valid TOML, JSON, or YAML, or prove that the final
configuration is valid after substitution.

## Findings and sources

### Editors and language servers

VS Code selects language mode using filenames and extensions. Its
`files.associations` setting can map custom suffixes to an installed language,
such as `"*.toml.template": "toml"`. This association is editor configuration;
it does not configure independent CLI checkers.
[VS Code language modes](https://code.visualstudio.com/docs/languages/overview).

The Taplo VS Code extension declares `.toml` and recognized lock filenames.
Neovim's commonly used Taplo LSP configuration selects the `toml` filetype.
Selecting the language is therefore part of enabling language-server support;
server installation, activation, and project configuration still matter.
[Taplo extension manifest](https://raw.githubusercontent.com/tamasfe/taplo/master/editors/vscode/package.json),
[nvim-lspconfig Taplo configuration](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/taplo.lua).

Neovim's detector strips `.in` and retries the underlying filename, except for
`configure.in`. It maps `.tmpl` to the `template` filetype, whose syntax loads
HTML. No equivalent generic stripping rule exists for `.template` in the
examined source. Custom patterns can be configured with `vim.filetype.add()`.
[Neovim filetype source](https://raw.githubusercontent.com/neovim/neovim/master/runtime/lua/vim/filetype.lua),
[template syntax source](https://raw.githubusercontent.com/neovim/neovim/master/runtime/syntax/template.vim),
[filetype documentation](https://neovim.io/doc/user/filetype/).

Language selection and schema selection are separate. VS Code JSON schemas have
`fileMatch` associations; Taplo provides schema directives, rules, and catalogs.
Renaming a file can require adjusting these associations even when language
detection works.
[VS Code JSON schemas](https://code.visualstudio.com/docs/languages/json),
[Taplo schema configuration](https://taplo.tamasfe.dev/configuration/using-schemas.html).

### Formatters and syntax checkers

Prettier infers a parser from the filepath. An explicit `--parser` or suitable
`--stdin-filepath` can supply the missing language for custom suffixes. This
applies to its supported languages; it does not imply built-in TOML support.
[Prettier parser options](https://prettier.io/docs/options).

Taplo defaults to finding TOML files and supports custom `include` globs.
Local probes found that its default filtering also skipped an explicitly passed
`.toml.template` file. A matching include configuration or stdin invocation
made it check the content. A zero exit status from the default invocation did
not establish that the file was valid.
[Taplo file configuration](https://taplo.tamasfe.dev/configuration/file.html).

### There is no universal template suffix

Established projects use different conventions. CMake documents `foo.h.in` as
input to `configure_file`. Helm recommends `.yaml` for templates producing YAML
and `.tpl` for templates producing no formatted content. Jinja permits arbitrary
extensions, discusses `.jinja` for editor plugins, and identifies `templates/`
as a useful directory convention. These conventions belong to their respective
engines; nix-seal does not implement Jinja or Helm's template language.
[CMake configure_file](https://cmake.org/cmake/help/latest/command/configure_file.html),
[Helm template practices](https://docs.helm.sh/docs/chart_best_practices/templates/),
[Jinja template filenames](https://jinja.palletsprojects.com/en/stable/templates/#template-file-extension).

## Validation and limits

Local probes used disposable synthetic files, clean Neovim detection, and the
repository development shell's Prettier and Taplo. No secrets were decrypted.

| Filename pattern | Clean Neovim | Prettier parser inference | Taplo default discovery |
| --- | --- | --- | --- |
| `app.<ext>` inside `templates/` | Underlying language | JSON/YAML detected | TOML checked |
| `app.template.<ext>` | Underlying language | JSON/YAML detected | TOML checked |
| `app.<ext>.template` | No match | No parser | Skipped |
| `app.<ext>.in` | Underlying language | No parser | Skipped |
| `app.<ext>.tmpl` | HTML-based `template` | No parser | Skipped |

Here `<ext>` means `toml`, `json`, or `yaml` for Neovim; JSON/YAML for Prettier;
and TOML for Taplo. Detection used empty contents to isolate filename behavior.
Content detection and user extensions can change the result. Additional Neovim
probes found `ssh_config.in` recognized as `sshconfig`, but an arbitrary
`config.gitconfig` had no match. Generic `.conf`, `.psk`, and invented format
extensions should not be assumed to select a suitable parser.

Taplo controls used deliberately invalid `broken = {{nix-seal:token}}` content.
Native TOML filenames failed checking; custom suffixes passed without reporting
that error. For `.toml.template`, an include rule matching `**/*.toml.template`
and a separate `taplo check --no-auto-config -` stdin check both reported syntax
errors. The default explicit-path case also skipped with `--no-auto-config`.

Python's standard JSON and TOML parsers accepted markers inside quoted strings
and rejected bare markers used as numeric values. Prettier with `--parser json`
also accepted a quoted marker. These observations establish source syntax only:
a placeholder string can still violate a schema's number, enum, or format
constraint. A substituted quote or newline can invalidate otherwise parseable
source. Correct escaping and validation of rendered output remain necessary.

These tests did not run a VS Code session, exchange LSP messages, validate every
application schema, or test every editor release. Editor/server activation
claims above come from upstream documentation and configuration source. No
filenames or runtime configuration were changed by this investigation.

## Implication for this repository

For future nix-seal defaults, prefer native names within an explicitly selected
template directory. Keep that directory beside its owning configuration or
reusable module; do not require a repository-wide layout or a `shared/local`
layer. Sources outside such a directory can use `app.template.toml` when an
explicit marker is helpful. Extensionless application files may need a scoped
editor association regardless of naming convention.

The current [named-source lookup](../nix-seal/nix/modules/shared.nix) appends
`.template`; implementing this recommendation would require a deliberate,
compatible lookup change and migration of examples. Explicit `source` paths
already allow other filenames. Directory naming should not imply automatically
activating every file it contains. No JSON template inventory is needed.

Check marker references on template sources, then check rendered examples with
synthetic values using the destination format's parser and, where available,
application schema. Keep real plaintext outside the Nix store and public check
logs. Public-value substitution alone leaves secret markers in `renderedSource`,
so that intermediate file is not necessarily suitable for final validation.
Templates containing extra transport metadata also need that metadata removed
before applying a parser for the destination format.
