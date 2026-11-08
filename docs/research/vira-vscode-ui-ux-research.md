# Vira VS Code UI and UX research

## Scope and licence boundary

Vira Theme is a commercial VS Code extension. Its terms permit use under a
non-transferable licence, but prohibit extracting source, copying or replicating
the product, and creating competing products from it. Consequently, the local
Carbon Neon theme should implement original UI decisions and use original icon
assets; it must not package, copy, or claim to be Vira. [Vira terms](https://www.vira.build/terms-conditions)

This note records publicly documented behaviour that is useful as a product
brief for the local VS Code theme. The official Marketplace listing says Vira
bundles dark colour themes, file icons, and product (UI) icons in one extension.
[Vira Marketplace listing](https://marketplace.visualstudio.com/items?itemName=vira.vsc-vira-theme)

## Features worth matching with original configuration

| Vira capability | Documented behaviour | Local Carbon Neon equivalent |
| --- | --- | --- |
| Cohesive theme family | Includes Carbon and a Carbon High Contrast variant, alongside other dark variants. | Keep `Carbon Neon` and `Carbon Neon OLED`; add a local `Carbon Neon High Contrast` variant only if it uses an independently designed higher-separation surface ramp. |
| One UI accent | `viraTheme.accent` affects the interface and icons; a custom six-digit hex accent overrides it. | Make `#80CBC4` the sole default interaction accent, and expose a declarative `appearance.carbonNeonAccent` option only if an accent selector can update all local targets consistently. |
| File and product icons | Vira ships matching file/folder and product-icon themes. | Use an independently licensed icon theme for now. Do not reuse Vira's icon font or SVGs. Keep file and UI icon choices deliberately aligned. |
| Theme/icon synchronisation | Switching a Vira UI theme synchronises its matching file-icon theme by default; it can be disabled. | Select the Carbon Neon colour theme and icon theme together from the single Nix selector. Do not override a user's explicitly chosen icon theme without an opt-in setting. |
| Tab orientation and contrast | Offers a top active-tab indicator and a contrasting tab-bar surface. | Set a teal active-tab indicator and a subtly raised tab bar in the local colour theme; use a visible but restrained tab contrast in the OLED variant. |
| Visual hierarchy controls | Offers subtle workbench borders, a solid active-line highlight, and an optional completely flat (no-shadow) appearance. | Use the Carbon surfaces (`#0A0A0A`, `#101213`, `#161718`) plus a readable neutral divider. Prefer a translucent active-line fill over an outline, and avoid blue for neutral chrome. |
| Reduced visual clutter | Hides Explorer arrows by default and offers outlined folder icons. | Preserve VS Code's accessible disclosure controls by default; do not remove navigation affordances globally. An alternate compact Explorer profile can be opt-in. |
| Typography control | Can disable italics for selected syntax scopes. | Keep italic comments/documentation as the default; offer a Nix option to disable italics through VS Code token customisation for users who prefer it. |
| Persistent colour overrides | Documents `workbench.colorCustomizations`, TextMate token customisations, and semantic-token customisations, including per-variant selectors. | Define Carbon Neon workbench, TextMate, and semantic token colours in the local extension. Keep small user overrides in `settings.nix`, scoped to `[Carbon Neon*]`, so they survive extension updates. |

The feature descriptions, including contrasted tabs, borders, solid active-line
highlight, icon synchronisation, outlined icons, Explorer-arrow hiding,
shadow removal, top tab indicator, and italic disabling, are from Vira's
official customisation guide. [Vira customisation guide](https://vira.featurebase.app/en/help/articles/6975827-customisation)

## Concrete design decisions for this configuration

1. Use Vira Carbon's documented interaction model, not its assets: teal is the
   universal focus, selected, link, button, and active-tab colour. The status
   bar, notification buttons, badges, and progress bars must use teal or a
   semantic colour—not VS Code's default blue.
2. Define every relevant VS Code workbench token in the local theme, especially
   `notification*`, `statusBar*`, `button*`, `badge*`, `progressBar.background`,
   `focusBorder`, `tab.activeBorder*`, `list.activeSelection*`, and terminal
   ANSI colours. This prevents a default blue from leaking into an otherwise
   Carbon UI.
3. Use a readable grey for inactive text and borders; reserve saturated colours
   for interaction and semantic states. The regular and OLED variants should
   differ in canvas blackness, not in semantic meaning.
4. Enable semantic highlighting and define semantic tokens alongside TextMate
   scopes. Vira's own guide explicitly distinguishes these two VS Code systems
   and recommends both for reliable customisation. [Vira semantic-colour guidance](https://vira.featurebase.app/en/help/articles/6975827-customisation)
5. Keep the existing smooth-scrolling, smooth-caret, ligature, compact-custom
   title bar, and disabled minimap preferences: they reinforce Vira's stated
   long-session, low-cognitive-load intent without reproducing proprietary
   implementation or branding. [Vira Marketplace listing](https://marketplace.visualstudio.com/items?itemName=vira.vsc-vira-theme)

## The blue “Quota reached” control

The solid blue in the supplied screenshot is not part of Vira Carbon's normal
status-bar or badge treatment. The current official Vira package's Carbon
theme uses the Carbon canvas for the status bar and teal for the activity badge
and remote-status foreground; its blue information-border token is a different,
thin validation role. It also leaves the warning and error status-item
backgrounds undefined. That makes the most likely cause an extension-provided
status item or an uncovered VS Code status-bar token, rather than a Carbon
syntax colour. The local theme should explicitly set the full status-bar and
notification token family, then identify the exact token with VS Code's colour
inspection tools if the tile remains. Preserve blue only for
information/validation states. This is an inference from the current published
Vira VSIX metadata and Carbon theme, not a claim about the specific quota
extension. [Official Vira VSIX package](https://marketplace.visualstudio.com/_apis/public/gallery/publishers/vira/vsextensions/vsc-vira-theme/latest/vspackage)

## Source check

This research used Vira's official Marketplace listing, Vira's official
customisation guide, and its published licence terms. The guide instructs users
to find its settings in VS Code with `@ext:vira.vsc-vira-theme`, and documents
that the native VS Code settings API—not hidden Vira-only behaviour—handles
workbench, TextMate, and semantic-token colour overrides.
