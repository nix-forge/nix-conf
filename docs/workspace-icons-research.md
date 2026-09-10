# Window icons inside workspace indicators

Reviewed: 2026-09-09. Scope: Noctalia 5.0.0, pinned at
`f96a407deb109c9db6f29db75e6fe487a5289e02`, with Hyprland. Waybar and
DankMaterialShell sources were retrieved on the review date.

## Answer

Use Noctalia's native taskbar grouped by workspace in the bar's center lane.
Keep a numeric label inside each capsule and show one icon per window. This
preserves workspace identity while making open windows visible and individually
selectable. The recommendation follows the existing shell's supported settings
and the comparable workspace taskbars below.

## Findings and sources

| Implementation | Useful behavior | Tradeoff for this configuration |
| --- | --- | --- |
| [Noctalia taskbar](https://docs.noctalia.dev/noctalia/bar/widgets/taskbar/) | Workspace capsules, internal labels, per-window icons, focus indicators, optional app grouping, theme color roles. | Already installed and shares shell styling. Requires compositor window-to-workspace assignments. |
| [Waybar Hyprland workspace taskbar](https://github.com/Alexays/Waybar/blob/master/man/waybar-hyprland-workspaces.5.scd) | Real image icons, icon-theme lookup, active-window styling, click commands, configurable icon limit. | Its `max-icons` removes duplicates before truncating. Copying this design into Noctalia would require more code or another bar. |
| [DankMaterialShell workspace switcher](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Modules/DankBar/Widgets/WorkspaceSwitcher.qml) | Optional grouping per app, separate grouping policy for the active workspace, focused-app styling, application-name fallback when icons fail, configurable maximum icons. | Its icon list uses `slice` at the configured maximum. A bounded list can hide windows; it is not evidence of an overflow menu. |

Noctalia's separate [workspaces widget](https://docs.noctalia.dev/noctalia/bar/widgets/workspaces/)
provides workspace tags and state styling, but has no application-icon setting.
The grouped taskbar is the supported route to the requested combined display.

Noctalia documents left-click to focus a window and middle-click to close it.
With app grouping enabled, clicks cycle that app's windows and overlay dots
indicate multiple windows. An active-window dot supplements the workspace state.
The label colors use `primary`, `secondary`, and `error` roles. Retain theme roles
instead of introducing fixed colors. [Taskbar reference](https://docs.noctalia.dev/noctalia/bar/widgets/taskbar/)

Inspection of the [pinned taskbar implementation](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/bar/widgets/taskbar_widget.cpp)
confirms these additional details:

- Workspace labels switch workspaces. Scrolling the grouped taskbar selects
  adjacent workspaces without wrapping. Right-clicking a window opens its menu.
- Grouped icons retain every window when app grouping is disabled. App grouping
  selects an active representative and keeps references for cycling windows.
- `taskbar_max_width` computes available title width. It does not cap the
  grouped icon list. The `+N` overflow belongs to dots mode only.
- Capsules use theme surface and primary roles with different active opacity.
  Workspace labels prioritize urgency over active and occupied state.

One icon per window is the clearest initial choice for direct selection. If a
dense session crowds the center, native app grouping reduces repeated icons
without discarding access to windows. That is a design recommendation, not a
claim that grouped icon mode handles arbitrary overflow.

## Validation and limits

This research inspected the locally fetched source selected by the
[package source pin](../pkgs/pkgs/by-name/no/noctalia-personal/source.nix), its
widget schema, rendering and interaction code, plus the linked upstream sources.
The generated Noctalia configuration was built from the complete working
directory on Linux and passed the installed shell's configuration validator.
The validator reports the same three existing warnings for the package's
symbolic-icon extensions. No new setting produced a warning. The full system
closure was not rebuilt.

After reloading the running shell, visual checks confirmed centered workspace
capsules, numeric labels, application icons, and active-workspace styling. Two
temporary windows of the same application appeared as separate icons in one
workspace. Moving one window to another workspace moved its icon into that
workspace's capsule. Both test windows were then closed. The generated theme
settings were unchanged.

Following visual review, the taskbar uses regular application artwork from the
configured icon theme and disables the active-window dot. The symbolic Ghostty
variant resolved to different artwork than the theme's regular application icon.
A live reload and screenshot confirmed the regular Ghostty icon and absence of
the dot. This setting applies to workspace window icons; other bar widgets keep
their existing icon policy.

Window focus and context-menu actions were inspected in source but not tested
with synthetic clicks. Urgency, multiple monitors, and very large window counts
remain untested. Grouped icons have no overflow menu; dense sessions can crowd
the bar. The implementation keeps every window visible rather than imposing an
icon limit that hides windows.

## Implication for this repository

Configure the grouped taskbar in
[the desktop Noctalia module](../homes/desktop/local/noctalia.nix), inheriting
existing bar styling and app-icon policy. Keep the workspace labels visible and
show inactive workspaces so the center remains useful for navigation.

## Design refinement, 2026-09-09

The follow-up question is how to make the centered workspace groups easier to
scan while retaining the theme, workspace numbers, and regular application
artwork. The source scope remains the Noctalia revision above. Apple Human
Interface Guidelines were retrieved on this date.

### Recommendation

Keep one rounded container per workspace and remove the filled disc behind its
number. Use neutral theme text for inactive workspace numbers and the existing
accent for the active number. Keep the active container's stronger fill and
outline. This gives selection a clear emphasis while leaving application
artwork recognizable. Use a consistent corner radius and icon size across the
groups; avoid shrinking the entire bar to make this one widget fit.

The design diagnosis is that the previous treatment repeats three competing
shapes: outlined capsules, colored number discs, and app icon silhouettes.
Filled cyan numbers make every occupied workspace demand attention even though
the icons already communicate occupancy. This is a design inference from the
rendering, not a measured usability result.

### Findings and sources

| Guidance | Application to the workspace groups |
| --- | --- |
| Apple's [Color](https://developer.apple.com/design/human-interface-guidelines/color) guidance discourages coloring the backgrounds of many controls and asks designers to use colors consistently. | Remove repeated filled number badges. Reserve strong theme color for selection and urgency. |
| [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) emphasizes alignment and hierarchy; the [HIG principles](https://developer.apple.com/design/human-interface-guidelines) emphasize harmonious concentric shapes. | Use one container shape per workspace, centered labels and icons, and consistent gaps. Extra nested discs add little information. |
| [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls) recommends consistent segment and content sizes for related choices. | Keep equal heights and icon sizes. These groups contain separate window targets, so they are not literal segmented controls. Variable widths preserve each window rather than hiding icons to force equal segments. |
| [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) recommends adaptive semantic colors rather than fixed values. | Reuse the configured theme's surface, foreground, primary, and secondary roles. Apple-inspired hierarchy does not require Apple's palette. |
| [Icons](https://developer.apple.com/design/human-interface-guidelines/icons?changes=l_8_2) distinguishes detailed app artwork from simpler interface glyphs and recommends visual consistency. | Keep the correct regular application icons, including Ghostty, with a shared size. Making all app artwork symbolic would lose the identity already verified above. |

### Native implementation and limits

The [pinned taskbar source](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/bar/widgets/taskbar_widget.cpp)
supports this refinement without changing the widget implementation:

- `minimal = true` clears workspace-number backgrounds while retaining their
  text and click targets. `occupied_color` and `focused_color` then color the
  text. The selected configuration uses `on_surface_variant` for inactive
  occupied numbers and retains the theme's `primary` for the focused number.
- Group capsules retain theme `surface_variant` fill and `primary` outline.
  Active and inactive opacities differ, so selection has a brightness cue as
  well as a different number color. The label color options do not control
  those outlines.
- `icon_scale` affects both icon tiles and the available height of inline
  numbers. Retain `icon_scale = 1` and full icon opacity for recognizable
  artwork. The base glyph size is 16 logical pixels; the bar's content scale
  and available height determine rendered dimensions. A common capsule radius
  of 6 logical pixels gives each group the same rounded rectangle shape.
- With minimal labels, empty-workspace text uses the widget foreground or
  `on_surface_variant` at reduced opacity. `empty_color` does not determine
  that text color. Set the common widget foreground to `on_surface` so empty
  labels retain more contrast after the opacity reduction.

### Refinement validation

The generated configuration built and passed the installed validator with only
the same three existing symbolic-extension warnings. A comparison with the
previous generated configuration confirmed that only the four workspace
presentation settings changed. The bar dimensions, theme palette, regular app
artwork, one-icon-per-window behavior, and disabled active-window dot remain.

Live captures on Linux confirmed aligned labels and icons, the selected and
unselected treatments, the existing group containing two different apps, and a
two-digit empty workspace. The original workspace and focused window were
restored after the check. The shell remained active.

Calculated contrast using the configured dark palette and native fill opacities
was approximately 4.83:1 for occupied inactive labels, 10.68:1 for the active
label, and 4.74:1 for inactive empty labels. These are design calculations for
foreground and background colors, not measurements of antialiased glyph edges
or a complete accessibility audit.

The earlier interaction validation remains a separate result. Arbitrarily
large window counts, alternate themes, and optical normalization of individual
third-party icons remain untested or outside native settings.
