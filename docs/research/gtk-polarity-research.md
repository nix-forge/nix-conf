# GTK variant selection under Stylix

Reviewed: 2026-09-27. Scope: GTK 3 dialogs, Stylix
`5e3809851f486e7fc7e84b40f174c74b60ecc784`, Home Manager
`4ac5a2ae9025eab1ebece4f9df8c315fd84a738a`.

## Answer

Keep the selected theme name, package, and palette. Request GTK 3's matching
variant with an overridable preference derived from Stylix polarity. Preserve
the theme's control styles, focus indicators, keyboard behavior, and application
preferences. A dark-only theme-name override prevents a future light appearance
from working naturally.

## Findings and sources

GTK 3's `gtk-application-prefer-dark-theme` requests an existing dark variant
of the configured theme. Applications can override settings. GTK 4 deprecated
this property in 4.20, so this integration sets it only for GTK 3.
[GTK 3 preference](https://docs.gtk.org/gtk3/property.Settings.gtk-application-prefer-dark-theme.html),
[GTK settings](https://docs.gtk.org/gtk3/class.Settings.html),
[GTK 4 deprecation](https://docs.gtk.org/gtk4/property.Settings.gtk-application-prefer-dark-theme.html).

Explicit Stylix polarity takes precedence. With `either`, use declared palette
variant metadata when present. The pinned Base16 library otherwise reports
`unspecified`, and Stylix's image generator emits colors without variant metadata.
The integration then compares background and foreground brightness to infer
appearance direction. That inference does not establish accessible contrast.
[Pinned Base16 metadata](https://github.com/SenchoPens/base16.nix/blob/75ed5e5e3fce37df22e49125181fa37899c3ccd6/lib/mk-scheme-attrs.nix),
[pinned image output](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/palette-generator/Stylix/Output.hs).

Stylix already owns the desktop color-scheme preference. Home Manager's GTK
`colorScheme` option also writes that preference. Setting only GTK 3's extra
configuration avoids a second owner and keeps GTK 4 and libadwaita on their
existing system preference path. High contrast is a separate preference.
[Pinned Stylix GNOME integration](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/gnome/hm.nix),
[pinned Home Manager GTK 3 integration](https://github.com/nix-community/home-manager/blob/4ac5a2ae9025eab1ebece4f9df8c315fd84a738a/modules/misc/gtk/gtk3.nix),
[libadwaita appearance](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/styles-and-appearance.html).

The pinned Stylix Flatpak workaround forces `GTK_THEME`, bypassing GTK 3's
variant preference. It also appends palette CSS only to `gtk.css`. The registered
repair retains the existing theme directory and read-only permissions, selects
the configured name with a `:dark` or `:light` variant, and appends generated
palette CSS to every existing ordinary, dark, and light stylesheet.
[Pinned Stylix GTK integration](https://github.com/nix-community/stylix/blob/5e3809851f486e7fc7e84b40f174c74b60ecc784/modules/gtk/hm.nix),
[GTK runtime override](https://docs.gtk.org/gtk3/running.html).

GTK 3 falls back to the ordinary stylesheet when a requested variant file is
absent. It cannot create a missing theme variant. `GTK_THEME` remains an upstream
Flatpak workaround, not a recommended global native-session setting.
[GTK 3 stylesheet loading](https://github.com/GNOME/gtk/blob/gtk-3-24/gtk/gtkcssprovider.c).

## Validation and limits

The [GTK check](../../tests/nix/gtk-polarity.nix) runs real GTK 3 dialogs under Xvfb
against generated settings and the flattened theme's Flatpak environment. Its
fixtures cover the four configured palettes, a light palette, `either`, absent
variant metadata, and a renamed theme package with a light stylesheet. Module
assertions cover explicit preference overrides and disabled theming.

On Linux, the matrix passed for 11 fixtures through both paths, totaling 22 GTK
dialog runs. The broader `theme-targets` and `temporary-package-fixes` checks
also passed. The live GTK 3 session passed after restoring the configured base
theme name and applying the generated preference file.

The [dialog probe](../../tests/gtk/check_dialog_contrast.py) requires at least 4.5:1
text contrast for ordinary enabled buttons in normal, hover, focused, and
backdrop states. This adopts the WCAG normal-text threshold as a native UI
regression criterion; it is not a claim of full accessibility conformance.
[WCAG contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).

The original light-base/dark-palette mismatch reproduced at 1.09:1. The native
dark-variant preference corrected the same dialog without changing widget CSS.
GTK 4 was checked separately on the live Linux session. The automated Flatpak
case exercises its generated theme and environment, not an actual sandboxed
application. Arbitrary future palettes, missing theme variants, high-contrast
mode, and application-specific styles still require runtime review.

## Implication for this repository

The [GTK target](../../modules/shared/stylix/targets/gtk/home.nix) owns the native
preference. The [temporary repair](../../overlays/temporary/stylix-gtk-flatpak-polarity.nix)
has a reviewed input revision and source guards. Remove it when upstream handles
variant selection and palette injection, then rerun the GTK check. The shared
dark polarity remains a default that profiles can override.
