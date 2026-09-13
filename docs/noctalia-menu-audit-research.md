# Noctalia menu consistency and usability

Reviewed: 2026-09-10. Scope: Noctalia 5.0.0 at
`f96a407deb109c9db6f29db75e6fe487a5289e02`, the personal package patches, and the
desktop menu configuration. This investigation extends the
[palette review](noctalia-theme-research.md) to menu geometry and interaction.
The audit began at root revision `7fd38c80a2aabdb16674fba7231496fa4a575bee`
and package revision `e2f597a2fc77ff2551ac5612086cb57c5cb8e554`.
Acceptance criteria came from the request for consistent menu appearance and
interaction, researched improvements, and fixes for discovered issues.
[Repository conventions](../CONTRIBUTING.md) govern ownership and validation.

## Answer

Keep the shared semantic palette and the existing corner-size hierarchy. The
strongest improvements are making menu placement predictable, giving icon-only
actions useful tooltips, leaving enough width for calendar headings, and hiding
disabled features from the Control Center Home page. These address specific
source behavior and observed layout problems without replacing the shell's
design system.

Treat floating versus attached menus as a deliberate design choice. Floating
menus give Control Center, session actions, launcher, and clipboard the same
outer silhouette. Attached menus retain an explicit connection to the bar.
Both can open near a clicked bar control. Check their placement and edges on the
actual output before choosing between them.

## Findings and sources

### Shared shapes already provide a coherent hierarchy

The pinned style defines corner radii of 3, 6, 9, and 12 logical pixels. Radius
helpers multiply these values by the control's local scale and the global
corner-radius scale. Smaller controls and larger containers therefore need
different radii. Circular avatars, radio buttons, and slider handles have a
different purpose and should retain their circular shape.
[Style tokens](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/ui/style.h#L13),
[radius scaling](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/ui/style.cpp#L70)

The [Stylix settings renderer](../modules/shared/stylix/targets/noctalia/settings.nix)
already selects radius scale 1.0, opaque panels, one font family, borderless
buttons and cards, and outlined inputs and popups. Keep that ownership. The
upstream settings distinguish panel outlines, popup outlines, input outlines,
and decorative card borders. Turning them all on would add visual weight to
every level of the interface.
[Shell appearance settings](https://docs.noctalia.dev/noctalia/configuration/shell/)

Attached panels intentionally use concave corners next to the bar and convex
corners away from it. Floating panels have ordinary rounded corners. This is
source behavior, not a broken radius setting. For attached panels, upstream
documents `bar.<name>.panel_overlap` as a per-output seam adjustment when
fractional scaling creates a visible cut. Change it only after reproducing a
seam on that output.
[Attached geometry](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/panel/attached_panel_context.h),
[fractional-scale seam guidance](https://docs.noctalia.dev/noctalia/getting-started/faq/)

### Open bar menus near their controls

The initial configuration left `open_near_click_control_center` and
`open_near_click_session` at their false defaults. The pinned implementation
centers attached panels along the bar when these options are off. Enabling
them uses the trigger's anchor and clamps the result to the bar's bounds.
Floating panels support the same behavior when their position is `auto`.
An explicitly fixed floating position disables near-click placement.
[Placement implementation](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/panel/panel_manager.cpp#L317),
[attached anchor placement](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/panel/panel_manager.cpp#L975)

Recommendation: enable near-click placement for Control Center and session
actions. Keep launcher and clipboard centered because their keyboard-driven
search workflows benefit from a stable screen position. Compare pointer opens
with keyboard opens, where a widget anchor may be absent.

### Give custom actions accurate tooltips

The initial `now-playing` control reused the launcher widget with a play glyph
and custom left/right actions. The pinned launcher creates an input area
without a tooltip, so it cannot explain either action. The supported
`custom_button` widget accepts a glyph, optional label, and tooltip while
retaining the ordinary bar action mechanism.
[Launcher implementation](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/bar/widgets/launcher_widget.cpp#L15),
[custom-button fields](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/bar/widgets/custom_button_widget_definition.cpp#L5)

Use `custom_button` for this static media entry and describe both actions in
its tooltip. A static play glyph does not report playback state; call the
control "Media controls" instead of implying that it is a live status
indicator. Preserve native status widgets where their glyphs or tooltips
communicate mute, connectivity, battery, or privacy state.

### Account for compact-sidebar width

`control_center.width` describes full-sidebar width. Compact sidebar mode
multiplies it by 0.85 before content scaling, and hidden-sidebar mode uses 0.75.
The initial setting of 680 therefore requests 578 logical pixels in compact
mode before content scaling. A value of 800 requests 680. Compare the longest
calendar heading and populated audio/media lists at the chosen width.
[Width calculation](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/control_center/control_center_panel.cpp#L78)

Keep the same sidebar mode for general and direct-tab opens so switching entry
points does not unexpectedly change navigation. The documented keyboard model
uses `tab_next` and `tab_previous` between sidebar and content, with arrows
inside each pane. Full labels improve first-use discovery but require more
space; compact navigation needs readable tooltips and visible keyboard focus.
[Control Center navigation](https://docs.noctalia.dev/noctalia/control-center/)

### Disabled weather leaves misleading Home content

The pinned Home page builds a weather row even when weather is disabled. Its
update method displays a disabled message, and the entire date/time card
always requests the Weather tab when clicked. Hiding the Weather tab does not
remove this row. The public configuration has no separate Home-card visibility
or identity-card layout options.
[Home construction and click action](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/control_center/tabs/home_tab.cpp#L453),
[disabled-weather text](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/control_center/tabs/home_tab.cpp#L1432),
[available configuration](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/config/config_types.h#L1524)

A focused package change should hide the weather row when disabled and open
Calendar from the date/time card in that state. The large identity card is a
separate design preference and needs a broader layout change. Do not enable a
network service merely to fill this card.

### Check interaction as well as appearance

Use WCAG guidance as a desktop design benchmark, not a claim of web compliance.
Measure clickable regions rather than glyph dimensions. The minimum-target
guidance uses 24 by 24 CSS pixels or sufficient spacing; visible keyboard focus
is a separate requirement. A 16-pixel glyph can be appropriate inside a larger
clickable region. Verify hover, focus, active, unavailable, and error states
with the actual palette.
[Target-size guidance](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html),
[visible-focus guidance](https://www.w3.org/WAI/WCAG22/Understanding/focus-visible.html)

Two upstream reports deserve targeted checks. Issue 4015 requests configurable
launcher category navigation; the pinned source still checks F6 directly.
This differs from the shell documentation's comment about Tab toggling
categories. Issue 3813 reports notifications intercepting clicks over fullscreen
applications on Hyprland. That report does not establish that the configured
revision reproduces it. Test notification expiry and dismissal before claiming
the fullscreen interaction is sound.
[Category-navigation request](https://github.com/noctalia-dev/noctalia/issues/4015),
[pinned F6 handling](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/shell/launcher/launcher_panel.cpp#L2246),
[fullscreen report](https://github.com/noctalia-dev/noctalia/issues/3813)

## Validation and limits

The initial research inspected the pinned source, package patches, repository
settings, and current primary documentation. The subsequent native Wayland audit
used a 3840 by 2160 output at scale 1.5. It reproduced the clipped calendar
heading at width 680, then confirmed that width 800 displays September 2026 in
full. Floating Control Center and session menus now share the launcher and
clipboard outline. Pointer opens follow the right and left bar controls,
respectively. Surface extents include shadow padding outside the screen; the
visible menu bounds remain inside it.

The media, search, and clock hover labels were inspected in the running shell.
The bar now requests 6-pixel capsule corners so hover backgrounds follow the
workspace shape. Native captures covered Home, Media, Audio, Monitor, System,
Power, Network, Bluetooth, Calendar, Notifications, Session, Launcher, Clipboard,
the audio-device popup, one application tray menu, Settings, a notification,
and the volume OSD. The
notification and OSD layers disappeared after their timeouts. Raw captures
remain outside the repository and are not publication artifacts.

The final personal package was built and loaded through the generated Noctalia
service and configuration. The same Home date-card click that previously
returned to Home now opens Calendar, and the disabled-weather row is absent.
The final hover capture confirms rounded rectangles on the bar. Weather-enabled
behavior follows the existing source path but was not exercised with a live
weather service.

Validation passed for native configuration parsing, the package build and its
bar-icon check, the root theme-target and four-palette contrast checks, package
independence, package policy, and package unit checks. The package flake also
evaluated on all supported systems. Formatting, whitespace, Markdown links, and
publication scans passed. This was a scoped Noctalia service update on Linux,
not a full NixOS activation. Its generated service closure is retained by a
private local GC root until a later declarative deployment supersedes it.

These checks do not certify every interaction. Fullscreen notification input,
all launcher category shortcuts, all third-party tray menus, multi-output
placement, and other output scales still need separate checks. Long device
names and notification previews deliberately truncate within bounded rows.

The executable source comes from
[the personal package pin](../pkgs/pkgs/by-name/no/noctalia-personal/source.nix).
The Noctalia input in [flake.lock](../flake.lock) supplies a different revision
for module integration. Record both when investigating future differences.
Runtime verification must cover the built personal package, including its
media and control-color patches.

## Implication for this repository

Keep palette and geometry choices in the Stylix target, interaction choices in
the desktop Noctalia configuration, and upstream behavior repairs in the
personal package. Validate the merged running configuration because GUI state
loads after declarative files. Finish by checking every enabled Control Center
tab, session menu, launcher, clipboard, tray context menu, notification, and
OSD for clipping, consistent focus/hover treatment, and correct dismissal.
[Configuration precedence](https://docs.noctalia.dev/noctalia/configuration/)
