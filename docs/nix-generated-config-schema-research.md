# Which configuration files should Nix generate and validate?

Reviewed: 2026-09-08. Scope: nix-conf and its nix-forge repositories, following
[the Noogle function review](noogle-function-research.md). The implementation
follow-up below records the adopted changes and their checks.

## Answer

Use Nix values to generate application configuration when settings vary by host,
share other configuration values, or currently require textual substitution.
The application still receives its native JSON, TOML, YAML or other format.
Prefer an existing NixOS or Home Manager module's typed `settings` interface
before creating another writer.

Versioned schemas are useful when they describe the installed application's
actual configuration contract. Pin the schema content and validator, validate
the generated file during its build, and update them with the application.
Keep application parsing and behavior tests for requirements the schema cannot
express. Merely adding a `$schema` URL does not enforce a build check.

## Concrete repository choices

| Files or component | Recommendation | Reason |
| --- | --- | --- |
| [SwayOSD module](../modules/home/desktop/osd.nix) | Generate an attribute set with `pkgs.formats.toml`. | The style path comes from Nix; text substitution inside TOML quotes can produce invalid syntax. An isolated quoted-path test reproduced this and the format generator passed. |
| [VS Code theme templates](../modules/home/vscode/settings.nix) | Consider Nix attribute sets and `pkgs.formats.json`, preserving the OLED include relationship and ordered rule arrays. | Colors already come from the shared Nix palette. This can remove the placeholder list and JSON text substitution. Validate final generated themes, retaining the existing editor/schema and visual tests. |
| [LinearMouse](../modules/home/linearmouse.nix) | Keep its existing JSON generator and add a schema check tied to the selected package version. | Generation is already appropriate. Its mutable staging and watcher behavior must remain intact. Upstream publishes version-specific schemas. |
| [Finder Favorites](../modules/home/macos/finder-favorites.nix) | Keep typed Nix options and JSON output; consider a versioned exported schema for external consumers. | `schemaVersion = 1` already identifies the application's format. A machine-readable schema would supplement native parsing, path checks and reconciliation tests. |
| [Actual](../modules/home/actual.nix) | Keep current structured JSON generation. Add an authoritative schema only if the selected app provides one. | Replacing `writeText` plus `toJSON` solely for spelling gives little benefit; schema checking is a separate improvement. |
| [Noctalia](../modules/home/desktop/noctalia.nix) | Pass Nix values to the Home Manager module for both baseline settings and its custom palette. | The initial review missed its `.toml.in` and `.json.in` baseline templates. The module already handles serialization and native configuration validation. |
| [Base16 palettes](../themes/default.nix) | Keep portable YAML unless Nix becomes their intended authoring interface. | These are small, static data sources. The pinned Stylix option also accepts an attribute set, so a future Nix migration can pass values directly instead of generating YAML only to read it back. |
| Root and subproject `pyproject.toml`, Cargo manifests, package manifests and lockfiles | Keep native source files. | Their own tools and non-Nix contributors need them as inputs. Nix can read and validate them. Generating them introduces a second authoring/build dependency with little benefit here. |
| `pkgs/by-name/*` source manifests, catalogs and license evidence | Keep updater-owned JSON and add versioned validation where useful. | The independent package updaters already own these data files. Moving them into Nix would complicate those workflows. |
| GitHub workflows, action metadata, Dependabot files | Keep committed YAML and shared CI validation. | GitHub must see these files before any Nix job can run. A Nix generator is possible only if its outputs remain committed and CI checks for drift; the existing shared-CI approach is simpler. |
| nix-seal schemas, migration fixtures and golden outputs; research evidence JSON | Keep these as schemas, fixtures or evidence. | They describe or test external representations. Generating expected fixtures from the same code under test would weaken independence. |
| Application-owned mutable files such as Codex's config | Preserve targeted runtime updates. | Replacing the complete file with an immutable generated file would discard application-owned settings or interfere with its writes. |

The palette observation comes from the locked Stylix `stylix/palette.nix`
`base16Scheme` option. The other local links identify inspected working files;
ongoing unrelated changes may not yet have public commits. GitHub's source-file
requirement is documented in its
[workflow documentation](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflows).
LinearMouse documents its
[version-specific schema support](https://github.com/linearmouse/linearmouse/blob/v0.11.4/Documentation/Configuration.md#json-schema).

## Select the correct format writer

The current root Nixpkgs lock is
`0968519e14f7aa7d3e9b389682bd74d2b51c8ce8`. Its
[format implementations](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/pkgs-lib/formats.nix)
expose `type` and `generate` for JSON, TOML and YAML. These types describe
serializable values; they do not define each application's accepted options.
In particular, `formats.json` has no schema-validation argument at this pin.

| Target representation | Starting point |
| --- | --- |
| JSON | Existing module settings, `pkgs.formats.json`, or `writeText` with `builtins.toJSON` |
| TOML | Existing module settings or `pkgs.formats.toml` |
| YAML | Select `pkgs.formats.yaml_1_1` or `yaml_1_2` for the consuming parser; `yaml` aliases 1.1 at this pin |
| INI | `pkgs.formats.ini` or `lib.generators.toINI`, checking the application's specific dialect |
| macOS preferences | Existing nix-darwin/Home Manager options or `pkgs.formats.plist` |
| XML, CSS, shell, Caddyfile and other specialized languages | Use the matching module/generator or retain a checked template; JSON escaping is not a general encoder |

A SwayOSD replacement can retain every current setting while letting the writer
encode the path:

```nix
xdg.configFile."swayosd/config.toml".source =
  (pkgs.formats.toml { }).generate "swayosd-config.toml" {
    server = {
      style = "${config.xdg.configHome}/swayosd/style.css";
      min_brightness = 5;
      show_percentage = true;
      max_volume = 100;
      keyboard_backlight = false;
      top_margin = 0.85;
    };
  };
```

This replacement is now implemented. The isolated build used the same values
and a synthetic path containing quotes and spaces; Python's independent TOML
parser confirmed the resulting values exactly. The old template failed to parse
that path. No SwayOSD process or desktop activation ran.

Generation can change key order, comments and formatting. Preserve ordered lists,
application-specific precedence, literal string values, and any byte-level
contracts. Avoid reading a generated derivation back into Nix evaluation;
pass the Nix value directly when a downstream module accepts it.

## Versioned schema policy

Keep two versions distinct. The application schema describes settings accepted
by an application release. The JSON Schema dialect, such as Draft 7 or 2020-12,
describes the schema language itself. In a schema document, the root `$schema`
declares that dialect. Sources: [dialect declaration](https://json-schema.org/understanding-json-schema/reference/schema)
and [schema identifiers](https://json-schema.org/understanding-json-schema/structuring).

For each useful schema validation target:

1. Select the schema from the application's exact source/release when possible.
   Otherwise record the schema revision tested with that application version.
2. Fetch the schema from the selected package source or an immutable upstream
   revision with a content hash. Do not keep application schema copies in this
   repository. Pin the validator through Nixpkgs as well. A version-looking URL
   alone does not fix its contents.
3. Pin referenced schemas too. A local schema containing HTTP `$ref` values
   can still request unpinned external data. Prefer a complete bundle or a
   local registry of canonical identifiers and pinned files.
4. Validate the generated file and install the checked output. Include negative
   tests so an invalid value demonstrably prevents the build.
5. Update the app, schema and compatibility fixtures together. If the package
   option is overridable, explicitly support the corresponding schema override
   or reject an untested version pairing.

Nix fetchers provide content hashing; Python jsonschema supports explicit
reference registries. Sources:
[Nixpkgs fetchers](https://nixos.org/manual/nixpkgs/stable/#sec-fetchers) and
[local schema registries](https://python-jsonschema.readthedocs.io/en/stable/referencing/).

A concrete output-validation wrapper can use the pinned `check-jsonschema`:

```nix
{ pkgs, schema }:
let
  generated = (pkgs.formats.toml { }).generate "example.toml" {
    port = 8080;
    enabled = true;
    label = "on";
  };
in
pkgs.runCommand "checked-example.toml" {
  nativeBuildInputs = [ pkgs.check-jsonschema ];
} ''
  check-jsonschema --schemafile ${schema} ${generated}
  cp ${generated} "$out"
''
```

Here `schema` must be an upstream schema from a pinned source or fixed-output
fetch that accepts the example fields. Point the installed configuration's
`source` at this derivation.
A separate flake check is also useful, but alone it only runs when that check is
requested. The installed checked output makes validation part of the file's
build dependency. The prototype verified this structure against a synthetic
schema; the implementation below also validates LinearMouse's release schema.
[Validator usage](https://check-jsonschema.readthedocs.io/en/latest/usage.html).

For schemas whose references are relative, `--base-uri` can select a pinned
local directory. It does not redirect absolute HTTP references. `--no-cache`
disables caching, not network access. Inspect and pin the entire reference graph.
The prototype resolved a relative reference locally despite an HTTP `$id` by
supplying a file base. A schema's `$id` defines identity/reference resolution;
it does not force validation or pin bytes.

Editor support is a separate convenience. A supported `$schema` field or an
editor file association can enable completion and diagnostics. Do not insert
`$schema` into a configuration whose application rejects unknown fields. VS Code
supports external `json.schemas` associations with local schema files.
[VS Code schema associations](https://code.visualstudio.com/docs/languages/json#_json-schemas-and-settings).

For VS Code themes, a downloaded core schema is not the whole contract. The
editor registers schema components and extensions contribute additional color
and token identifiers. Preserve the existing
[theme-schema research and runtime checks](vscode-theme-schema-research.md)
rather than declaring every extension-specific key invalid from a static list.

For nix-seal's own formats, keep Rust structures, exported versioned schemas and
runtime protocol checks in agreement. The existing
[plan-v2 schema](../nix-seal/schemas/plan-v2.schema.json) already declares its JSON
Schema dialect, while the Rust implementation owns the protocol identifier and
semantic checks. A schema should not become a second manually maintained source
of truth for the same Rust data model.

## Validation and practical limits

The schema prototype used the root Nixpkgs pin above and check-jsonschema 0.38.0
on x86_64 Linux. Generated JSON, TOML, YAML 1.1 and YAML 1.2 passed the same local
Draft 2020-12 schema. A string supplied for the required integer port rendered
successfully but failed the subsequent validation build. Invalid IPv4 format
was rejected, and the local relative-reference test passed.

The validator normalizes TOML dates and times into strings. Both native TOML
dates/date-times and quoted string equivalents passed the prototype's string
schema. Its YAML parser also normalizes timestamps and mapping keys for JSON
compatibility. Passing a schema therefore does not prove the application sees
the same native types. Keep parser tests for any such values actually used.
Sources: [pinned TOML parser](https://raw.githubusercontent.com/python-jsonschema/check-jsonschema/0.38.0/src/check_jsonschema/parsers/toml.py)
and [pinned YAML parser](https://raw.githubusercontent.com/python-jsonschema/check-jsonschema/0.38.0/src/check_jsonschema/parsers/yaml.py).

Unknown keys are rejected only when the schema restricts them. Supported
`format` checks depend on the validator and its configuration. Schema defaults
normally describe behavior instead of inserting values into the application
configuration. Schema validation cannot prove paths/devices exist, permissions
are right, services can bind their ports, or theme contrast is usable.

Keep plaintext secrets out of generated store files and continue the existing
runtime secret injection. Validate public structure at build time and perform
any necessary secret-dependent validation in the runtime flow.

## Implementation follow-up

SwayOSD now uses `pkgs.formats.toml`; both obsolete TOML source files were removed.
The [module regression check](../tests/nix/generated-configs.nix) parses its actual
generated file with Python's TOML parser and checks every setting, including a
style path containing spaces, quotes and a backslash.

The Carbon Neon and OLED themes now use Nix attribute sets and `pkgs.formats.json`.
`pkgs.linkFarm` assembles the extension source with the native package manifest.
An exact parsed-JSON comparison using distinct palette values passed for both
themes before removing the templates. Ordered rules, alpha suffixes and the
OLED include path are preserved. The editor still receives the same JSON filenames.

LinearMouse's [package metadata](../pkgs/pkgs/by-name/li/linearmouse/source.nix)
pins the v0.11.4 configuration schema by content hash alongside the application.
The updater changes both pins atomically and leaves the previous file intact if
fetching the schema fails. The module validates its generated JSON before staging
it for installation. Its mutable staging path, watcher behavior and activation
permissions are preserved.

The module requires matching package/schema version metadata by default. An
alternate package can set `programs.linearmouse.settingsSchema` explicitly to a
pinned local schema. All references must be bundled; the build rejects external
references before validation. The validator comes from the locked Nixpkgs input.
Linux configuration checks pass for valid settings, invalid-setting rejection,
external-reference rejection, the version guard and an explicit schema override.
Updater tests cover paired pins and failed-schema recovery.

The full desktop closure built successfully on x86_64 Linux. Package-repository
`just check`, `just lint` and `just test` passed. Against VS Code 1.133.0, the built
extension passed runtime interaction checks for both theme variants and 40 syntax
probes across 12 languages for each variant. The schema check validated both theme
documents and their manifest and rejected all four invalid canaries. This repeats
the existing targeted checks, not every view or language-server behavior described
in the separate theme audit.

These changes do not convert native manifests, workflows, static palettes or
independent fixtures. Their recommendations in the table above still apply.
The configured Darwin home's checked LinearMouse settings derivation evaluates
successfully. No deployment or activation was performed. LinearMouse's native
macOS behavior requires a separate smoke test on Darwin.

## Complete `.in` follow-up

The first implementation missed active `.in` configuration sources. The follow-up
inventory found 48 such files in nix-conf. Eleven now use structured Nix values,
one literal TOML file was renamed, and 36 language-specific templates remain.
The other six nix-forge repositories had no `.in` files in their inspected trees,
including the `.github` repository's GitHub tree.

| Former template | Current source and generator |
| --- | --- |
| `noctalia.toml.in` | [Baseline settings](../lib/desktop/noctalia.nix), passed to `programs.noctalia.settings`; Home Manager generates TOML and validates it with the selected Noctalia package. |
| `noctalia-carbon-neon.json.in` | [Palette values](../lib/desktop/noctalia-carbon-neon.nix), passed to `programs.noctalia.customPalettes.Stylix`; Home Manager generates JSON. |
| `ironbar-config.toml.in` | [Ironbar values](../lib/desktop/ironbar-config.nix), rendered by `pkgs.formats.toml` in the existing module. |
| `swaync-config.json.in` | [Notification values](../modules/home/desktop/notifications.nix), rendered by `pkgs.formats.json`. |
| `hypridle.conf.in` | [Idle module](../modules/home/desktop/idle.nix), using `lib.hm.generators.toHyprconf` with ordered listener blocks. |
| `hyprpaper.conf.in` and `hyprpaper-wallpaper-entry.conf.in` | [Wallpaper module](../modules/home/desktop/wallpaper.nix), using the same generator with repeated monitor blocks. |
| `cliphist.conf.in` | [Clipboard module](../modules/home/desktop/clipboard.nix), using `lib.generators.toKeyValue` with the application's space separator. |
| `darktable-Info.plist.in` | [Darktable module](../modules/home/darktable.nix), using `pkgs.formats.plist` and a native boolean for Retina support. |
| `languagetool-http-server.properties.in` | [LibreOffice module](../modules/home/libreoffice.nix), using `pkgs.formats.javaProperties` for LanguageTool's numeric settings. |
| `server-extensions.conf.in` | [Local-control module](../homes/macbook-pro-m4/local/local-control.nix), using `lib.generators.toINIWithGlobalSection` for OpenSSL certificate extensions. |
| `walker-config.toml.in` | Initially renamed to literal TOML. The writer follow-up below replaces it with [Nix settings](../modules/home/desktop/walker.nix), TOML generation without a locally maintained schema. |

Static desktop settings live in their owning modules under `modules/home/desktop`. Parameterized configuration
builders and validators live under `lib/desktop`, exporting named functions through
the repository library loader. The PowerShell writer lives under `lib/writers`,
and the local-control configuration builder under `lib/local-control`. Their
callers and checks use the library exports. The framework recursively imports
`.nix` files beneath selected feature directories without a `default.nix` boundary;
placing data functions inside `modules/home/desktop/config` would make it call
those functions as Home Manager modules. Noctalia also disables Stylix's
generic Noctalia target, because this module already maps Stylix colors and owns
the palette, opacity and layout. This avoids conflicting definitions after the
settings become a mergeable Nix attribute set.

The retained files are intentional source templates:

| Count | Files | Reason to retain templates |
| --- | --- | --- |
| 25 | Bash templates in `modules/home/desktop/scripts`, `modules/home/dev/scripts`, `modules/home/dev/agentic-tui/scripts`, and `modules/nixos/virtualisation/scripts` | These are executable programs with command paths and runtime logic. Their existing Nix writers and substitutions remain the appropriate interfaces. Moving the entire programs into Nix strings would retain the same shell code and add another layer of escaping. |
| 5 | `hyprshell.css.in`, `ironbar-style.css.in`, `swaync-style.css.in`, `swayosd-style.css.in`, `walker-style.css.in` | CSS selectors and declarations remain CSS. The optional Walker module now consumes its stylesheet; all five substitute theme values and run GTK parser checks. |
| 2 | `Bootstrap.ps1.in`, `Test-Baseline.ps1.in` | PowerShell provisioning and verification programs, including ordered Windows operations. |
| 1 | `Autounattend.xml.in` | The Windows seed renderer supplies runtime provisioning values and credentials outside the Nix store. Preserve its XML escaping, semantic recipe fingerprint and independent seed tests. |
| 1 | `proxy.Caddyfile.in` | Specialized Caddy routing and mTLS configuration with environment-supplied credentials. Conversion to native JSON would require a separate route/authentication equivalence review. |
| 1 | `vorssaint-sudoers.in` | A constrained sudoers rule. Generic INI or key/value escaping does not implement sudoers syntax. |
| 1 | `karakeep-extension-setup.md.in` | User-facing Markdown instructions with a substituted server URL. |

The `.in` suffix alone does not identify a data format or a missed migration.
To repeat the working-tree inventory, including hidden directories:

```sh
rg --files --hidden -g '*.in' -g '!**/.git/**'
```

Noogle's [key/value generator](https://noogle.dev/f/lib/generators/toKeyValue/)
and [INI global-section generator](https://noogle.dev/f/lib/generators/toINIWithGlobalSection/)
helped select the smaller writers. The locked Nixpkgs implementations remain
authoritative for `formats.plist` and `formats.javaProperties`; the Hyprland-format
generator belongs to Home Manager's `lib.hm`, not Nixpkgs' `lib.generators`.

Exact parsed-value comparisons passed for both converted Noctalia files,
Ironbar and SwayNC, preserving all arrays and distinct palette values. The
[template regression check](../tests/nix/template-configs.nix) also exercises the
actual Home Manager modules with a quoted/backslash-containing font, repeated
Hypridle listeners, multiple Hyprpaper monitors and bounded clipboard settings.
The existing Ironbar check covers quoted theme names and command strings.
The actual Darwin Darktable plist also preserves every original value and type.

The final full desktop closure built successfully on the desktop host, including
Noctalia's native TOML validation and the LanguageTool properties derivation.
Both focused template and Ironbar checks passed. The built LanguageTool file
preserves all four numeric settings as Java property strings. OpenSSL 3.5.1
accepted the generated server extensions when issuing a disposable test
certificate. Darwin configuration evaluation and plist parsing passed; no native
macOS app launch or system activation ran. Nix formatting, Python lint/type
checks and documentation checks passed for the changed files.

## Writer and configuration follow-up

The follow-up audited structured files and their producers as well as `.in`
files. The selected Nixpkgs input resolves to revision
`0968519e14f7aa7d3e9b389682bd74d2b51c8ce8`. A lockfile node named `nixpkgs`
can belong to a different input; resolve the root input alias before researching
its available functions.

### Choosing a writer after substitution

`replaceVarsWith` performs strict placeholder substitution. Its `postCheck` hook
can validate the result, but repeating executable packaging and checks at every
caller is unnecessary. The [shared Bash template writer](../lib/writers/bash.nix)
now passes the rendered file directly to `writers.writeBash` or
`writers.writeBashBin`. A shared checker validates the complete resulting script.
`writeShellApplication` remains useful when a script can be assembled as text and
needs declared runtime dependencies, but its default shell options can change
behavior.
See the [pinned substitution implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/replace-vars/replace-vars-with.nix)
and [Noogle shell application reference](https://noogle.dev/f/pkgs/writeShellApplication/).

Python writers accept a source path or a derivation directly. This composes
strict substitution with interpreter packaging and Flake8 without reading build
output during evaluation:

```nix
let
  rendered = pkgs.replaceVars ./helper.py.in {
    configurationPath = builtins.toJSON "/etc/helper/config.json";
  };
in
pkgs.writers.writePython3Bin "helper" { } rendered
```

Pass `rendered` directly. Interpolating it into a string makes the writer treat
the pathname as program text. `builtins.readFile rendered` instead introduces
import from derivation. The LibreOffice settings helper has no placeholders, so
it now passes its source path directly to `writers.writePython3`. Only Flake8's
line-length rule is disabled because repository formatting uses Ruff. See the
[pinned writer implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/writers/scripts.nix)
and [Noogle Python writer reference](https://noogle.dev/f/pkgs/writers/writePython3Bin/).

### Walker configuration without a local schema

Walker settings live in [Nix](../modules/home/desktop/walker.nix).
The [generator](../lib/desktop/walker-config.nix) uses `pkgs.formats.toml`.
Walker 2.17.0 has no published JSON Schema; its configuration contract lives in
its [Rust configuration types](https://github.com/abenz1267/walker/blob/v2.17.0/src/config.rs).
The local subset schema and its fixed-version upgrade guard have been removed
so package updates do not require maintaining a second copy of that contract.

The build verifies TOML generation. It no longer rejects Walker-specific unknown
keys, incorrect setting types, incomplete prefix records, or out-of-range
application values. Walker interprets settings when loading the file. If upstream
publishes a schema, consume it from the selected package source or a versioned,
content-hashed URL, as LinearMouse already does. Do not add a local schema copy.

The [optional Walker module](../modules/home/desktop/walker.nix) consumes the
generated file and themed CSS when `desktop.walker.enable = true`. This does not
enable Walker in an existing profile or replace its selected launcher. Build the
saved configuration independently with
`nix build .#checks.x86_64-linux.walker-config`.

### Other formats and newly converted files

| Format or file | Implementation and validation |
| --- | --- |
| Fontconfig XML | The duplicate-emoji filter and its XML writer check were removed. The [Google design package](../pkgs/pkgs/by-name/go/google-fonts-design/finish.py) already removes the duplicate emoji providers before installation. |
| OpenSSL client extensions | The [local-control module](../homes/macbook-pro-m4/local/local-control.nix) now generates the remaining client extension file with `toINIWithGlobalSection`, matching its server extension generator. |
| Electron flags and modprobe options | Ordered Nix lists and `lib.concatLines` preserve the native lines, including repeated Electron flags. No application-specific parser is implied by this generator. |
| GTK CSS | The five desktop templates remain CSS. A [GTK 4 parser](../lib/desktop/check-gtk-css.c) checks their rendered output in `postCheck`, including `parsing-error` signals. The pinned consumers all use GTK 4. Warnings are reported; parser errors fail the build. Hyprshell font names now escape quotes and backslashes before substitution. |
| PowerShell | The [file writer](../lib/writers/powershell.nix) parses both rendered Windows guest scripts and runs pinned PSScriptAnalyzer rules, including Windows PowerShell 5.1 syntax compatibility. It fails on errors and warnings without executing the scripts. Native Windows cmdlet behavior still requires runtime tests. |
| Caddyfile | The local-control template runs `caddy adapt --validate` with public fixture values and disposable certificates. This checks parsing, adaptation, and module provisioning without starting a service. Deployed certificates and runtime credentials still need runtime validation. |
| Windows unattended XML | Retains the existing runtime seed renderer and escaping checks because credentials are substituted outside the Nix store. |
| Libvirt XML | Retains the existing version-matched `virt-xml-validate` checks. |

`pkgs.formats.xml` uses xmltodict and checks XML syntax with xmllint. It supports
attributes, text, and repeated elements, but an attribute set cannot preserve
arbitrary mixed content or interleaved sibling order. `builtins.toXML` writes
Nix's XML representation of Nix values, which is unsuitable for application
configuration. The pinned format set has no dedicated CSS, PowerShell, or
Caddyfile generator. Use their native syntax and a consumer-specific validator.
See the [XML format implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/pkgs-lib/formats.nix),
[GTK parser signals](https://docs.gtk.org/gtk4/signal.CssProvider.parsing-error.html),
[PowerShell parser API](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.parser.parsefile?view=powershellsdk-7.4.0),
and [Caddy command reference](https://caddyserver.com/docs/command-line).

The remaining native files include package and Cargo manifests, lockfiles,
GitHub workflows, linter and editor configuration, static theme inputs,
versioned schemas, updater-owned source metadata, independent test fixtures,
and reviewed evidence. Package-owned Fontconfig snippets remain in the package
repository so package builds do not depend on the workstation configuration.
These files have native consumers or independent ownership; moving them into
this repository's generation path would add coupling or a bootstrap step.

### Follow-up validation

The original focused run included Walker subset-schema rejection cases and
Fontconfig DTD validity. Those checks were removed with the local Walker schema
and duplicate Fontconfig filter. Current checks retain GTK error detection and
non-executing PowerShell validation; see the [coverage guide](generated-file-checks.md)
for the expanded rules, behavior tests, and aggregate command.
The Home Manager template check also builds all five stylesheets using a font
name containing quotes and a backslash, plus the optional Walker module's TOML.
All focused checks passed. The generated Walker TOML preserves every original
parsed value and array order; the former Fontconfig check preserved both exclusions.
The missing-file CSS canary initially exposed an unchecked I/O error domain in
the new checker. The corrected checker rejects it as well as invalid CSS.

The complete desktop closure built on the desktop host, including the actual
rendered PowerShell scripts, Python writer, and system Fontconfig integration.
The LibreOffice profile-path regression passed. Caddy adapted the public fixture
configuration, and OpenSSL issued disposable certificates with the expected
client/server usages and server alternative names. The local-control Home
Manager module evaluated successfully for aarch64 Darwin, including its
assertions. No system activation, Windows script execution, native macOS launch,
or production Caddy provisioning ran.

## Executable writers after substitution

The final implementation uses the path-input API of `pkgs.writers`. These
functions read a rendered derivation during the build. Passing the derivation
directly avoids both import from derivation and treating a store pathname as
literal program text. The selected Nixpkgs revision remains
`0968519e14f7aa7d3e9b389682bd74d2b51c8ce8`.

| Function | Suitable input and checks |
| --- | --- |
| `writers.writeBash` and `writers.writeBashBin` | Accept the rendered file. Add a Bash interpreter line and executable layout. Supply an explicit `check`; these writers have no default Bash check. |
| `writers.writePython3` and `writers.writePython3Bin` | Accept the rendered file and provide Python plus its configured libraries. Flake8 runs by default. Keep `doCheck` enabled; the built-in check overrides a custom `check` argument. |
| `writers.writeDash` and `writers.writeDashBin` | Accept the rendered file but need an explicit checker. Use for standalone POSIX-shell programs after verifying their interpreter requirements. |
| `writers.writeFish` and `writers.writeFishBin` | Accept the rendered file and run Fish's non-executing parser by default. |
| `writers.makeScriptWriter` | Generalizes the same composition for an explicit interpreter, checker, and optional wrapper arguments. It always adds an interpreter line. |
| `concatTextFile` | Concatenates generated file paths and accepts an explicit `checkPhase`. It can preserve an existing interpreter line but has no language-specific checks. Its checker uses `file`, not `target`. |

These interfaces are documented by [Noogle's Bash writer](https://noogle.dev/f/pkgs/writers/writeBashBin/)
and [generic script writer](https://noogle.dev/f/pkgs/writers/makeScriptWriter/).
The [pinned script writers](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/writers/scripts.nix)
and [text builders](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/trivial-builders/default.nix)
establish the actual input handling and checks.

The shared helper composes strict substitution, shebang normalization, and the
Bash writer. It removes only a recognized, argument-free Bash shebang from the
rendered file, then lets the writer add its own interpreter. Other shebangs fail
instead of silently changing interpreters. It preserves source `set` options,
command substitutions, and existing runtime dependency paths. Single-file,
`bin`, and `libexec` destinations retain their existing calling conventions.
The single-file writer returns a symlink to its internal executable; callers
continue to use that file path. Bin outputs receive `meta.mainProgram`.

The writer's `check` runs a checker built with `writeShellApplication`. That
checker uses `stdenv.shellDryRun` and `shellcheck-minimal` on the complete generated
script. Strict shell options apply to the checker, not automatically to the
application. This verifies the application body, including text introduced by
substitution. A wrapper containing only `exec /store/script` would not provide
that coverage. The implementation uses public writer arguments rather than
extracting another derivation's `checkPhase` or overriding `textPath` internals.

Modules receive the repository library as `myLib`. For example:

```nix
myLib.writers.writeBashTemplate { inherit pkgs; } {
  name = "example-helper";
  dir = "bin";
  src = ./scripts/example-helper.sh.in;
  replacements = {
    bash = lib.getExe pkgs.bash;
    configurationPath = lib.escapeShellArg "/etc/example/config.json";
  };
}
```

`makeWrapperArgs` on the upstream writers can supply runtime PATH entries or
environment variables when needed. The migrated commands already substitute
absolute executable paths or explicit runtime paths, so they retain those
settings. Existing direct Python writers continue to use their built-in checks.
CSS, XML, Caddyfile, PowerShell guest files, and sourced shell fragments retain
their format-specific handling. A script writer that adds a Unix shebang is not
appropriate for every file produced by substitution.

The [Bash writer checks](../tests/nix/bash-writers.nix) cover the three output
layouts, quoted replacement values and arguments, a single interpreter line,
metadata, invocation through a named symlink, preservation of shell options,
and non-executing validation. Negative
cases introduce invalid syntax and an unquoted argument through substitution so
the checks must examine the final script body.

The migration covers 60 Bash template sources: desktop tools, browser and editor
helpers, VM controls, the Nix workload launcher, the Python compilation hook,
local-control commands, the Wi-Fi profile materializer, and seven MiniDV tools.
The five sourced setup fragments and UWSM environment data remain plain rendered
files. Their caller controls the interpreter and shell environment.

Validation on 2026-09-08 passed the writer's positive and negative build tests,
template configuration regressions, desktop command regressions, and LibreOffice
profile-path check with import from derivation disabled. The complete desktop
system closure then built successfully on its native Linux host. No activation
was performed. The MiniDV command-forwarding functions require a documented,
local exception for ShellCheck SC2119 and SC2120 because zero arguments are valid
for the wrapped external commands. Other ShellCheck rules remain enabled.

The Darwin local-control Home Manager fixture evaluated its package derivations,
launchd command, activation dependencies, and assertions successfully with import
from derivation disabled. This is evaluation evidence, not a native Darwin build
or runtime test. Formatting and Deadnix passed for the changed Nix files. Statix
passed for the new helper and tests; its existing findings in the wallpaper and
Nix workload modules also occur in the pre-migration snapshot.

## Non-Bash languages and embedded configuration

The follow-up audit on 2026-09-08 found useful changes in Python, Lua, and
Nushell. It covered the workstation modules and inspected the nested package,
framework, and secret-management repositories. Package updater modules and test
suites retain their existing directory structure because they import sibling
modules and are not individual installed commands.

| Language | Applied change |
| --- | --- |
| Python | Helium's CRX converter and preference initializer, the VMware host resolver, and both Jujutsu identity callers now use `writers.writePython3Bin`. Existing Dock and Gecko writers consume source paths directly. |
| Lua | mpv's plugin now passes through `myLib.writers.checkLuaFile`, which compiles without running the chunk, lints it with only the host's `mp` global allowed, and preserves non-executable source bytes. |
| Nushell | PATH lists and literal environment values use Home Manager's serializer. The final merged `config.nu`, `env.nu`, and `login.nu` files gain parser checks through `home.extraDependencies`. |

Python launchers now invoke the packaged command so its writer owns the
interpreter. Flake8 remains enabled. The local E501 and W503 exceptions accommodate
the repository formatter's line lengths and leading binary operators; they do
not disable syntax or undefined-name checks. The Python writer accepts raw paths
and rendered derivations, as described by
[Noogle](https://noogle.dev/f/pkgs/writers/writePython3Bin/) and its
[pinned implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/writers/scripts.nix#L1178-L1265).

An mpv plugin needs the application's injected API. The Lua checker uses the Lua
implementation exposed by the selected mpv package, calls `loadfile` without
calling its returned function, and runs Luacheck with `mp` as a read-only global.
A standalone `writeLua` executable would add an unnecessary interpreter line.
The pinned writer also ignores its `libraries` argument and replaces a supplied
`check` argument. See the
[writer source](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/writers/scripts.nix#L964-L1020),
[Lua loading semantics](https://www.lua.org/manual/5.2/manual.html#pdf-loadfile),
and [mpv scripting API](https://mpv.io/manual/stable/#lua-scripting).

Nushell's previous PATH construction inserted raw text into a list. A path with
spaces could become multiple entries. Its environment renderer also inserted
unescaped quotes, backslashes, and newlines. The revised renderer serializes
literal segments separately from supported shell-style self references. It
preserves both a conditional colon and a conditional colon plus existing value.
For example, `head${VAR:+:$VAR}` becomes `head:prior` when `VAR` is `prior`,
and `head` when it is empty. The custom renderer lives in
[lib/shells/nushell.nix](../lib/shells/nushell.nix). Serialization follows
[Home Manager's pinned implementation](https://github.com/nix-community/home-manager/blob/693e8ce0fb240a73c116a03cfd7b19269c87af88/modules/lib/nushell.nix).

`nu-check --debug` parses the complete files and follows their `source` and `use`
imports. The checker converts a false result into build failure and runs with a
temporary home and configuration directory. Imported completion files must be
store dependencies; runtime-only private imports cannot be validated this way.
The checks do not execute startup commands or imported `export-env` blocks.
[Noogle's `writeNu`](https://noogle.dev/f/pkgs/writers/writeNu/) confirms that its
executable writer supplies no default checker. The chosen file validation uses
[Nushell's parser command](https://www.nushell.sh/commands/docs/nu-check.html)
and leaves ownership of the generated files with the
[Home Manager module](https://github.com/nix-community/home-manager/blob/693e8ce0fb240a73c116a03cfd7b19269c87af88/modules/programs/nushell.nix).

The JavaScript audit found no standalone local program needing a new launcher.
The pinned `writeJS` uses `writeText`, expects source text, and provides no
JavaScript syntax check. Its behavior differs from the derivation-aware Python
writers. A future JavaScript executable would need an explicit Node `--check`
step and an explicit choice of CommonJS or ES modules. Existing JavaScript test
programs retain their test-runner layout. See the
[JS writer implementation](https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/build-support/writers/scripts.nix#L1076-L1097)
and [Node syntax-check option](https://nodejs.org/api/cli.html#-c---check).

Existing PowerShell, GTK CSS, XML, and Caddy validators remain appropriate for
their consumers. `formats.xml` checks well-formedness; Libvirt's selected schemas
provide additional application validation. Browser CSS cannot use GTK's grammar.
These files gain nothing from an executable script writer.

The [non-Bash checks](../tests/nix/non-bash-writers.nix) exercise CRX v2 and v3
payload extraction, one-time preference initialization, Python CLI entry points,
Lua byte preservation and non-execution, unknown Lua globals, and invalid syntax
in Lua and substituted Nushell. Nushell fixtures exercise generated imports,
PATH values containing spaces and quotes, literal environment escaping, and
empty and nonempty self references. All focused checks pass on Linux with import
from derivation disabled.

The full Nushell module, including its completion imports, passes the fixture.
The same quoting cases fail against the pre-change environment and PATH
generators. Existing VMware resolver, Dock, Gecko registry, and protected
identity tests also pass. Nix formatting, Deadnix, Statix, shell formatting,
Markdown checks, and local documentation links pass for this change.

The complete desktop system built successfully on its native Linux host. Its
current profile selects Bash, so Nushell coverage comes from the dedicated
module fixture rather than that system build. The Darwin system derivation
evaluated with import from derivation disabled. No activation was performed;
native Darwin builds and live mpv playback remain untested.
