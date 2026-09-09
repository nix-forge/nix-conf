# Extending Stylix with repository theme targets

Reviewed: 2026-09-08. Scope: the repository's theme integration and Stylix
revision `5e3809851f486e7fc7e84b40f174c74b60ecc784` from [flake.lock](../flake.lock).

## Answer

Keep the palette and theme selection shared. Put application styling in a
separate target tree, imported by the shared Stylix feature. Use
`stylix.targets.<name>` for its controls, so users can disable a target without
disabling the application. Application modules should own installation,
services, shortcuts, profiles, and other behavior.

Use Stylix's documented external-module pattern. Its `mkTarget` argument is
injected by its own loader and is unavailable to ordinary imports. External
targets can declare their enable option with `config.lib.stylix.mkEnableTarget`
and guard configuration with both `stylix.enable` and the target's enable
option. [Adding modules](https://nix-community.github.io/stylix/modules.html)
documents this route.

This investigation concerns module ownership and controls. The earlier
[theme comparison](stylix-theme-research.md) concerns palette selection.

## Findings and sources

### Target controls

The pinned [target helpers](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/stylix/target.nix)
give `mkEnableTarget name true` a default equal to `stylix.autoEnable`. Setting
`autoEnable = false` changes defaults; an explicit target enable still works.
Setting `stylix.enable = false` must suppress every local target's output.

Neither this helper nor the pinned
[`mkTarget` implementation](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/stylix/mk-target.nix)
automatically checks application installation. Custom targets that write files,
install extensions, or set service properties need the relevant application or
desktop feature enable guard. Optional third-party modules also need an option
existence check before defining their options. Check option presence when
constructing the module, rather than choosing imports from evaluated config.

For targets that already exist upstream, reuse their enable option. Add a
clearly named local control for the native theme or additional styling. This
provides separate controls for disabling all styling and returning to the
upstream renderer. New application targets can declare their own enable option.
This is a repository design recommendation, not an upstream extension API.

### Augmenting and replacing output

Prefer an extension when upstream already owns most of an application's theme.
Use ordinary module merging and `mkDefault` for local defaults. Where a native
theme replaces generated output, disable the corresponding upstream component
and give each resulting setting one owner.

The pinned [Spicetify target](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/spicetify/spicetify.nix)
writes its theme and color scheme in one colors component. A native theme can
disable that component through `stylix.targets.spicetify.colors.enable` while
retaining the main target enable control. Disabling the local native-theme
control should release that component to upstream again.

VS Code needs special care. Its
[colors component](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/vscode/each-config.nix)
installs the generated extension, but its
[font settings](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/vscode/templates/settings.nix)
also select the `Stylix` color theme. Disabling upstream colors therefore does
not remove the theme-name assignment. Keeping upstream font configuration
requires a narrowly documented override of `workbench.colorTheme` when the
native theme is active. Honor the upstream `profileNames` option rather than
assuming a profile named `default` in reusable styling code.

The pinned [Noctalia target](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/noctalia/hm.nix)
separates colors, polarity, opacity, fonts, and wallpaper. Its adapter checks
whether the Noctalia option exists. Local styling can replace the components
it owns while preserving a single target enable switch. Application startup,
plugins, and hardware-dependent settings belong in the application module.

Avoid replacing upstream modules with `disabledModules` for this separation.
The repository's [override policy](../overlays/README.md) treats source repairs
and module replacements as temporary fixes with a registry and revision review.
Ordinary supported target options avoid that maintenance burden.

### File and platform boundaries

Use a shared feature entry point with explicit NixOS, Home Manager, and Darwin
imports. Place each application's theme module and assets together beneath the
theme feature, using platform-specific entry points where needed. Keep data
helpers outside automatic module discovery. The
[framework contract](../nix-config-framework/README.md#layout-and-selectors)
requires shared envelopes and gives directories with `default.nix` an explicit
feature boundary.

Local observation before migration: styling appears in editor, music, browser,
terminal, and desktop feature modules, while the shared Stylix feature already
owns theme selection and semantic colors. Separate Firefox and Zen selectors
also configure upstream targets. The migration should centralize those settings
without requiring users to select both an application and its theme module.

The pinned [Home Manager integration](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/stylix/home-manager-integration.nix)
copies system settings only through its automatic integration. This repository
already disables automatic imports and selects shared features through its
framework. Preserve that import ownership. Explicitly define which system
defaults attached homes inherit, and keep standalone homes evaluable without
`osConfig`. Linux desktop adapters must remain inactive on Darwin.

### Security and performance

Keep theme assets in the Nix closure and use the existing pinned package
sources. This reorganization needs no runtime downloads, network listeners,
privileged service, or new update mechanism. Keep credential handling and
application security policy with their existing owners. These are design
constraints, not results of a security audit.

Prefer structured program settings where available, so callers can override
individual values. Keep CSS rendering in derivations when the consumer accepts
a file. For consumers requiring an in-memory string, substituting a checked-in
template avoids building a derivation merely to read it back. The
[Stylix contributor guidance](https://nix-community.github.io/stylix/modules.html)
recommends structured settings and warns against reading generated files during
evaluation. No new background process is needed for target discovery or palette
selection. Runtime icon synchronization already required by a desktop feature
should remain bounded to that feature.

## Validation and limits

Research resolved the Stylix store source through the local flake and inspected
the pinned loader, target helpers, target generator, Home Manager integration,
and relevant upstream adapters on Linux. Official web documentation and the
revision-specific source were consulted on the review date. Initial requests to
guessed documentation URLs failed; the documented `modules.html` page was then
retrieved successfully.

This note records source inspection and a design recommendation. It does not
claim implementation tests, package builds, visual validation, activation, or
Darwin runtime validation. The implementation should evaluate enabled and
disabled targets, `stylix.enable = false`, `stylix.autoEnable = false`, absent
applications, native-theme fallback, and attached and standalone homes. Compare
generated theme values across the supported palettes. Full desktop builds must
follow the [build-placement rule](../AGENTS.md).

## Implemented layer

The [theming guide](theming.md) documents the resulting target tree and controls.
The implementation uses the existing target enable switches, adds
`custom.enable` for native replacements and styling additions, and keeps
application behavior in its original modules. Chromium theme defaults use
`mkOptionDefault` so they merge with the existing default extension set.

Validation on Linux passed the target contracts, generated desktop files,
desktop and browser integration contracts, policy JSON checks, and eight Codex
appearance-updater tests. The full desktop system built on the desktop host.
The configured Darwin system and Darwin target contracts evaluated successfully.
Formatting, Nix lint, Markdown links, and the theme-tree secret scan passed.

Validation used explicit local path inputs for the existing framework and
secret-management submodule work, without writing the lockfile. No activation,
Darwin build, or live visual comparison was performed. A before-and-after
configuration comparison matched VS Code, Spotify, Codex, Ghostty, Hyprland,
Hyprlock, and the palette. Noctalia's icon and dock styling moved into its main
settings from its feature settings file; the generated-file checks validate the
resulting native configuration.
