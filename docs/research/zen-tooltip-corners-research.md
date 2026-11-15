# Zen hovering UI corner rendering

Reviewed: 2026-10-09. Scope: Linux Wayland tooltips and native popup UI in Zen 1.22.3b,
Hyprland 0.56.0 plus revision `e368c13`, GTK 3, and adw-gtk3.

## Answer

The strongest upstream match is compositor clipping of Firefox tooltip
subsurfaces. Hyprland discussion
[#12554](https://github.com/hyprwm/Hyprland/discussions/12554), opened on
2025-12-05, reports intact tooltip borders with compositor rounding set to zero
and truncated corners with rounding enabled. The maintainer attributes the
behavior to Firefox using a subsurface for the tooltip. This is a hypothesis
for Zen's interrupted tooltip outline until an isolated comparison confirms it.

Changing the tooltip's CSS cannot prevent a compositor from clipping its
finished image. That explains why a CSS workaround may leave the symptom
unchanged, but it does not prove which layer caused a particular capture.

## Findings and sources

### Rendering layers

The exact installed Hyprland revision is
`e368c13c27a42a173b9e08fa0bf413f9f7073187`. Its renderer calculates rounding
from the parent window and monitor scale, then copies that value to every
surface in the parent surface tree. The element renderer subtracts one pixel
and applies that rounding without exempting non-main surfaces. Its separate
popup rendering path sets `dontRound` to true. This explains why a tooltip
that enters the subsurface path needs a different investigation from an
`xdg_popup` menu or panel.
[Parent rounding](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/render/Renderer.cpp#L603),
[surface traversal](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/render/Renderer.cpp#L702),
[element rounding](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/render/ElementRenderer.cpp#L310),
[popup path](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/render/Renderer.cpp#L776).

Window rules match window metadata, such as the parent's app ID and title.
The inspected rule properties and effects have no subsurface selector or
subsurface-only rounding exemption. A tooltip implemented as a subsurface
therefore cannot receive a separate rounding rule while its parent retains
compositor rounding. A browser-wide `rounding = 0` rule would also change the
main browser window. These conclusions concern this revision's built-in rules;
they do not exclude a renderer patch or plugin.
[Window matching](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/desktop/rule/windowRule/WindowRule.cpp#L383),
[match properties](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/desktop/rule/Rule.hpp#L13),
[rule effects](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/desktop/rule/windowRule/WindowRuleEffectContainer.hpp#L9).

Native hovering UI must be classified by its actual protocol role. The
tooltip hypothesis does not establish that context menus, browser menu panels,
extension panels, or website CSS popovers share the same cause. Capture and
compare each affected type independently before applying a common repair.

### Browser popup role selection

Mozilla bug [1992860](https://bugzilla.mozilla.org/show_bug.cgi?id=1992860)
reports different native effects for context menus and tooltips depending on
whether they fit inside the browser window. The GTK widget maintainer explains
that Firefox avoids move-to-rect placement when the popup fits the top-level
window, and may use subsurfaces instead. Mozilla closed the report INVALID.
The linked [Hyprland discussion #11650](https://github.com/hyprwm/Hyprland/discussions/11650)
covers right-click menus, download panels, and extension panels. The browser
and compositor maintainers disagree on who should handle that behavior.
Neither discussion establishes a shipped corner-rendering repair.

Current Mozilla GTK code supports both roles for popup UI, rather than assigning
all menus to one role. Permanent panels receive a utility hint. Other popup
types can switch between the menu and utility hints according to whether
move-to-rect placement applies. Tooltip hints work with both placement
methods. The code declines move-to-rect for layout-constrained popups and
incompatible popup hierarchies. This source inspection used Mozilla revision
`83cebcf5a522bf49667fd07084f04e8497de0eba`; it is not a claim that every branch
condition was verified in the installed Zen binary.
[Popup configuration](https://github.com/mozilla-firefox/firefox/blob/83cebcf5a522bf49667fd07084f04e8497de0eba/widget/gtk/nsWindowWayland.cpp#L1468),
[hint switching](https://github.com/mozilla-firefox/firefox/blob/83cebcf5a522bf49667fd07084f04e8497de0eba/widget/gtk/nsWindowWayland.cpp#L827),
[layout constraint](https://github.com/mozilla-firefox/firefox/blob/83cebcf5a522bf49667fd07084f04e8497de0eba/widget/gtk/nsWindowWayland.cpp#L792),
[hierarchy constraints](https://github.com/mozilla-firefox/firefox/blob/83cebcf5a522bf49667fd07084f04e8497de0eba/widget/gtk/nsWindowWayland.cpp#L1083).

GTK 3's Wayland backend chooses a real popup for menu hints, a parent and input
grab, or move-to-rect positioning. Otherwise a temporary window with a mapped
transient parent can become a subsurface.
[GTK role selection](https://github.com/GNOME/gtk/blob/0f3aa454a2a14b68e2753f63bedb2c74bd45b54b/gdk/wayland/gdkwindow-wayland.c#L3213).

The preference `widget.wayland.use-move-to-rect` defaults to true. It enables
eligible placement, rather than forcing every popup to use `xdg_popup`.
Disabling it can send more UI through the direct-placement path. No supported
preference to force all native hovering UI to use real popups was identified.
[Preference definition](https://github.com/mozilla-firefox/firefox/blob/83cebcf5a522bf49667fd07084f04e8497de0eba/modules/libpref/init/StaticPrefList.yaml#L21179).

Historical [Mozilla bug 1785185](https://bugzilla.mozilla.org/show_bug.cgi?id=1785185#c18)
explains why the backend switches hints when changing placement methods.
[Bug 1967082](https://bugzilla.mozilla.org/show_bug.cgi?id=1967082) records
XWayland and move-to-rect preference comparisons for context-menu flicker.
Those reports support using a fresh VM profile with `MOZ_ENABLE_WAYLAND=0`
as a diagnostic comparison. They do not validate that setting as a repair for
the corner-outline symptom.

adw-gtk3 gives tooltips a 9px radius, an 80% opaque black background,
`background-clip: padding-box`, and a 1px border. These settings can affect
contrast and the appearance of transparent edges. They are separate from
compositor clipping. The inspected source is revision
`47922ed96562c002696ad2d2d80383f2ad30dc93`.
[Theme tooltip source](https://github.com/lassekongo83/adw-gtk3/blob/47922ed96562c002696ad2d2d80383f2ad30dc93/src/sass/widgets/_tooltip.scss).

The initial configuration had two relevant overrides. A Zen stylesheet disabled
native appearance and supplied a CSS border and radius in both browser profiles.
The [GTK target](../../modules/shared/stylix/targets/gtk/home.nix) supplied an opaque
popover background and changed background clipping to `border-box`. Both
workarounds were removed on 2026-10-09 at the user's request. Their comments
described earlier theories, and neither could restore pixels discarded by the
compositor. The normal GTK theme selection and palette polarity repair remain.

### Issues, pull requests, and discussions

| Source | Reported behavior and relevance |
| --- | --- |
| [Hyprland discussion #12554](https://github.com/hyprwm/Hyprland/discussions/12554) | Closest match. Rounded compositor clipping truncates Firefox tooltip corners. The maintainer reported no targeted solution at the time of the discussion. |
| [Hyprland issue #5333](https://github.com/hyprwm/Hyprland/issues/5333) | Older Firefox popup rendering report. Comments distinguish subsurfaces from popups and describe different rendering when a popup crosses the parent window boundary. It supports testing tooltip placement, but does not establish the current cause. |
| [Hyprland issue #11590](https://github.com/hyprwm/Hyprland/issues/11590), [merged PR #13124](https://github.com/hyprwm/Hyprland/pull/13124) | The PR merged on 2026-01-31 and fixes opaque-region bounds used for occlusion. This is a related renderer repair, not evidence that tooltip corner clipping is fixed. |
| [Mozilla bug 1765691](https://bugzilla.mozilla.org/show_bug.cgi?id=1765691) | Firefox 101 multiline tooltips lost their right border on Wayland but not XWayland. The reporter later marked it WORKSFORME and attributed recovery to bug 1798697. The symptom differs from four missing corner arcs. |
| [Mozilla bug 1258086](https://bugzilla.mozilla.org/show_bug.cgi?id=1258086) | Historical GTK 3 alpha-tooltip painting regression, VERIFIED FIXED in the Firefox 49 development cycle with fixes also recorded for 47 and 48. Its existence does not justify an old graphics preference workaround for current Zen. |
| [Hyprland discussion #15102](https://github.com/hyprwm/Hyprland/discussions/15102) | Fractional scaling caused missing or flashing Firefox tooltips and crashes. A participant reported the problem no longer reproducible with Firefox 152.0.6 and Hyprland 0.56.0. This is a different symptom and is not a guarantee for Zen's outline. |
| [Zen issue #3844](https://github.com/zen-browser/desktop/issues/3844) | Rounded web-content clipping on macOS. It concerns the page viewport, not Linux tooltip windows. |

Searches of Zen's upstream tracker for `tooltip border`, `tooltip corner`,
and tooltip pull requests found no change that specifically repairs this
outline symptom. This is a search result, not proof that no relevant issue or
unindexed discussion exists. Hyprland searches included tooltip and subsurface
rounding pull requests. The related occlusion PR above has a concrete scope;
the other matches did not establish a tooltip-specific repair.

## Validation and limits

This note records source research and configuration inspection. It does not
claim a completed graphical reproduction. A private NixOS VM test was prepared
with the installed Zen and Hyprland packages, a fresh profile, synthetic local
content, and tooltip and context-menu captures at rounding values 16 and zero.
Nix syntax parsing and Python compilation passed. Neither result establishes
that the VM boots or reproduces the artifact.

The VM build was submitted through `workstation-task`, but another long-running
build held the workstation queue throughout this investigation. The queued
invocation was cancelled before it executed. No guest screenshot or protocol
trace was obtained. VM execution and a visual pass/fail check remain outstanding.
No browser or compositor setting was changed during this investigation.

The installed browser, compositor,
monitor, and pointer must remain untouched during runtime diagnosis.

An isolated virtual machine should use a fresh Zen profile and synthetic local
HTML with both a `title` tooltip and a CSS-drawn tooltip. Compare the same scene
with compositor rounding enabled and disabled. Then compare native appearance
with the repository stylesheet, integer and fractional output scales, GTK theme
variants, and a second compositor. Change one variable at a time.

Capture the Wayland protocol trace in that machine to establish whether the
affected tooltip uses `wl_subsurface` or `xdg_popup`. A visual improvement with
rounding disabled identifies compositor clipping only when the browser, theme,
scale, placement, and tooltip size remain constant. A result under Xvfb alone
does not exercise the Wayland subsurface path.

Raw traces, full desktop captures, and profile data belong outside the
repository. Record only reviewed results and narrowly cropped synthetic
evidence here. A VM software renderer also cannot establish that a host GPU
driver produces the same pixels.

## Implication for this repository

Do not add another GTK or browser preference patch based only on the existing
comments. First test compositor clipping in isolation. If that comparison
confirms the cause, choose the smallest compositor or browser change that
preserves the desired window appearance and passes the same tooltip capture.
Until then, the existing overrides are candidates for review, not demonstrated
repairs.

## Follow-up on a durable repair

Research revisited on 2026-10-09. The question is whether a repair can preserve
Zen's native UI and the main window's rounded corners. This section records a
proposed renderer design. No patch, graphical reproduction, or deployment has
validated it yet.

### Upstream status and broader evidence

Hyprland main at revision `663b29b846e4bad17cfa29941f6d2fbb6b61f139`, retrieved
on 2026-10-09, still traverses the window's subsurfaces with the parent's
rounding value. The element renderer then passes that rounding to each surface
texture draw. Updating to this inspected revision would therefore retain the
source mechanism implicated by discussion #12554. That observation does not
exclude an independent browser or GTK change that avoids this path.
[Current traversal](https://github.com/hyprwm/Hyprland/blob/663b29b846e4bad17cfa29941f6d2fbb6b61f139/src/render/Renderer.cpp#L726),
[current element rendering](https://github.com/hyprwm/Hyprland/blob/663b29b846e4bad17cfa29941f6d2fbb6b61f139/src/render/ElementRenderer.cpp#L311).

Two older requests concern the same design problem. Issue
[#1558](https://github.com/hyprwm/Hyprland/issues/1558) asks the compositor to
stop rounding subsurface corners; it is closed as not planned. Issue
[#3296](https://github.com/hyprwm/Hyprland/issues/3296) asks for separate tooltip
rounding and is closed without a linked implementation in the retrieved page.
Issue [#5610](https://github.com/hyprwm/Hyprland/issues/5610) reports compositor
rounding affecting foot's scrollbar and URL labels. These sources support
including ordinary embedded subsurfaces in a regression test rather than
building a browser-only exception.

Searches of the upstream GitHub issue and PR index for `subsurface rounding`,
`tooltip rounding`, and PRs containing `clip rounding` found no targeted repair.
The known merged occlusion PR #13124 changes region bounds, rather than the
rounding coordinate system. Search coverage remains a limitation; closed
requests and a lack of matching results do not prove that every relevant branch
or discussion has been found.

### Preferred compositor design

If isolated tests confirm compositor clipping, pursue a Hyprland renderer
repair that evaluates window rounding in the parent window's coordinates.
The current renderer rounds each texture's own rectangle. A small tooltip
well inside the browser consequently receives four new compositor corners.
A shared parent-coordinate mask would leave that tooltip's own pixels intact
while retaining the outer window's shape. This is a design inference from the
inspected source, not an upstream accepted fix.

The installed OpenGL path already supplies a top-left position and full size
to its rounding shader, and the shader evaluates `gl_FragCoord` against them.
Those arguments currently come from the texture draw box. That provides a
concrete starting point for separating the texture box from the window rounding
box in render data. A patch must carry the chosen geometry through all texture
and blur paths, and transform it consistently with scale, monitor coordinates,
animations, and offscreen passes. Changing only the radius or `mainSurface`
branch would not establish those properties.
[Uniform setup](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/render/OpenGL.cpp#L1560),
[rounding shader](https://github.com/hyprwm/Hyprland/blob/e368c13c27a42a173b9e08fa0bf413f9f7073187/src/render/shaders/glsl/rounding.glsl#L11).

Niri provides an implementation precedent. Its v0.1.6 release describes
rounded geometry clipping that supports subsurfaces while preserving opaque
regions and eligible overlay-plane rendering. Its pinned clipping helper
passes a transform into the shared geometry's coordinates; the shader clips
against that geometry and evaluates rounded alpha there. This supports testing
a geometry-aware shader rather than requiring a full-window framebuffer for
every window. It does not establish that copying Niri's implementation into
Hyprland would be correct.
[Release design](https://github.com/niri-wm/niri/discussions/350),
[clipping helper](https://github.com/niri-wm/niri/blob/2c82b77a7116a1241ea2fd41dd008ff00b609aae/src/render_helpers/clipped_surface.rs),
[geometry shader](https://github.com/niri-wm/niri/blob/2c82b77a7116a1241ea2fd41dd008ff00b609aae/src/render_helpers/shaders/clipped_surface.frag#L44).

There are two limits to address before calling this a complete repair.

First, a subsurface may extend outside its parent. The core Wayland protocol
explicitly permits this and does not automatically clip it to the parent's
area. A full rounded-rectangle clip can therefore truncate legitimate native
UI when it crosses the browser boundary. Niri's documentation acknowledges
that Firefox uses subsurfaces for some menus and that geometry clipping can
cut them off. A proposed Hyprland change should make its policy explicit.
For a repair limited to compositor rounding, preserve content outside the
parent rectangle and remove only the rounded corner cutouts inside that
rectangle. Full clipping to window geometry would be a separate policy choice.
Both policies still clip a tooltip that overlaps a parent's actual corner
cutout. The subsurface role alone does not tell the compositor whether the
child is a tooltip or ordinary embedded content.
[Subsurface specification](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_subsurface),
[Niri clipping caveat](https://github.com/niri-wm/niri/wiki/Configuration:-Window-Rules#clip-to-geometry).

Second, overlapping child buffers at an antialiased outer corner need explicit
verification. Multiplying each layer's alpha by the same fractional mask can
produce a different edge from compositing the layers first and masking the
result once. For example, two opaque overlapping draws with mask coverage 0.5
can compose to alpha 0.75 instead of 0.5. A shared geometry shader fixes the
coordinate error but does not by itself prove group-compositing equivalence.
A framebuffer composite followed by one mask is a useful reference result.
A production implementation could use sample coverage, a stencil approach, or
a limited offscreen fallback, depending on upstream renderer constraints.
This edge case and these remedies are rendering analysis, not claims about an
existing upstream patch.

### Alternatives and their tradeoffs

| Approach | What it can fix | Why it is not the preferred permanent repair |
| --- | --- | --- |
| Set rounding to zero only for the Zen main window | Removes the inherited compositor radius if that is the cause. | Removes the compositor's rounding from the main browser window too. It is a narrow temporary fallback after VM confirmation. |
| Exempt every non-main surface with `dontRound` | Removes the added corners from tooltip buffers. | Embedded content or an opaque child covering a window corner can bypass the main window's shape. It also leaves damage, blur, and occlusion policy unresolved. |
| Compose the full surface tree into a framebuffer and round once | Provides group masking with consistent alpha at overlap edges. | Adds rendering and memory cost, may reduce direct-scanout or overlay eligibility, and must preserve out-of-parent content and popup ordering. Use as a reference or bounded fallback. |
| Change Firefox or GTK to use `xdg_popup` for eligible transient UI | Sends that UI through Hyprland's existing unrounded popup path. | Needs toolkit and browser ownership, placement, input-grab, and nested-popup tests. No verified preference or ready patch forces every affected native UI into that role. |
| Change GTK or Zen CSS radius, transparency, or border | Changes the client-drawn shape. | Cannot restore pixels the compositor has discarded. Retain only theme changes with an independently measured benefit. |
| Run Zen through XWayland | Avoids this particular native Wayland subsurface route. | Changes the display backend and can affect scaling and popup behavior. Treat it as a diagnostic comparison or a measured fallback. |

The browser alternative remains appropriate when a specific transient needs
to escape parent corner clipping or needs shell popup semantics. Mozilla's
role-selection constraints above explain why a global hint replacement needs
more review than a cosmetic preference change. The renderer alternative also
benefits clients that use subsurfaces as ordinary window content.

### Acceptance matrix for an isolated VM

The first VM pass should establish the mechanism with the installed packages.
Only then compare a candidate renderer against both the failing baseline and
a zero-rounding reference. Keep the browser profile, content, theme, dimensions,
and placement identical within each comparison. The matrix below is a proposed
acceptance requirement, not a record of completed tests.

| Fixture or variation | Required result |
| --- | --- |
| Native title tooltip completely inside the browser | Client border and corner arcs match the zero-rounding reference, with the main browser window still rounded. |
| Context menu, browser menu panel, download panel, and extension panel | Record each protocol role. Test interior and boundary placements independently; every affected type needs its own before/after evidence. |
| Synthetic CSS tooltip inside the page | Its pixels remain unchanged by the repair. |
| Synthetic opaque child at each actual outer-window corner | Child content respects the intended main-window shape instead of filling its corner cutouts. |
| Nested child buffers and foot scrollbar or URL overlay | Interior rectangles keep their own shape; traversal and stacking remain correct. |
| Subsurface partly outside the parent; separate `xdg_popup` | Preserve the chosen overflow policy. Shell popups retain their own placement and client shape. |
| Overlapping opaque and translucent children at the outer edge | Compare against compositing first and masking once; no compounded antialias opacity or seams. |
| Output scales 1, 1.25 or 1.5, and 2; monitor transforms | Mask coordinates, border alignment, and hit-testing remain consistent. |
| Move, resize, workspace animation, and fullscreen transition | No stale clipped region, blinking edge, or stranded tooltip pixels. |
| Blur and transparency enabled and disabled; partial occlusion | Blur stays within the intended shape, background updates correctly, and removed corners do not claim opaque coverage. |
| Screencopy and window capture | Captured geometry agrees with the displayed result without clipping or exporting stale content. |
| Static scene and embedded video | Interior subsurfaces keep their rendering optimizations where possible; any frame-time or memory cost is measured and reported. |

Inspect damage and opaque regions as well as screenshots. Incorrect occlusion
can remove the background behind apparently transparent corners even when the
foreground shader is correct. Trace protocol roles in the VM, and retain raw
logs outside the repository. A software-rendered VM pass must state that GPU
and overlay behavior on physical hardware remains unverified.

### Integration recommendation

Do not deploy a guessed renderer edit or another theme workaround on the
interactive desktop. Complete the VM reproduction, then prototype the shared
window-coordinate design with explicit overflow policy and edge-overlap tests.
Choose an upstreamable renderer patch if that prototype passes; use a Zen-only
zero-rounding rule if an interim workaround is wanted and its appearance is
acceptable. Any local package patch must follow the repository's
[override lifecycle](../../overlays/README.md), including a removal condition and
review guard. The research follow-up did not change settings or packages. The subsequent implementation is recorded below.

## Renderer implementation

The local package now has a candidate renderer patch in
[hyprland-subsurface-rounding.patch](../../overlays/temporary/patches/hyprland-subsurface-rounding.patch).
It leaves interior child textures without an independent compositor radius.
When a child overlaps a parent corner band, it composites the surface tree
into an existing work framebuffer and applies one mask using the parent bounds.
Decorations stay outside that group. The shared mask runs after blur composition
and also applies to mirror output. It preserves pixels outside the parent
rectangle. Animation scaling remains separate from the parent-bound size clamp.
The renderer collects the complete traversal before classifying corner overlap,
so children stacked below the parent use the same geometry and keep their order.

The grouping path retains conservative empty opaque coverage. Ordinary interior
children use the existing draw path without an extra framebuffer. Group output
avoids applying window tint a second time. If framebuffer allocation fails, the
renderer keeps blur and uses the parent-coordinate mask per layer. That fallback
preserves corner geometry but can compound fractional alpha at overlapping edges;
it is a stated degradation under resource pressure, not group-mask equivalence.

The override is separate from the existing subsurface lifetime repair, and the
selected package retains both patches. Its review guard pins the inspected
Hyprland revision. Remove it when the upstream renderer implements the intended
surface-tree behavior and passes the regression.

[The VM check](../../tests/hyprland/subsurface-rounding-vm.nix) uses a synthetic
Wayland client rather than a real browser profile. It compares an interior square
child with a zero-rounding reference, compares two identical opaque layers with
a single-layer parent at all four outer corners, includes translucent layer
references, and checks legal overflow at negative offsets and right/bottom edges.
It includes a child stacked below the parent, where overlapping antialiased
edges still require a single final mask.
The candidate cases request output scales 1, 1.25 and 2 with blur off and on;
the oracle rejects a requested scale that the guest output did not actually apply.
It also reads back radius and blur options rather than relying on command exit status. The edge comparison permits two RGB units for work-buffer color
conversion. That tolerance still needs confirmation against the actual captures.
The baseline check requires an explicit wrong-pixel failure. A setup error does
not count as reproducing the defect.

Run the checks with:

```sh
workstation-task nix build .#checks.x86_64-linux.hyprland-subsurface-rounding-baseline -L
workstation-task nix build .#checks.x86_64-linux.hyprland-subsurface-rounding -L
```

The candidate patch applies cleanly to the pinned source. Nix parsing, focused
Python linting and type checking, and the Wayland client's C syntax check pass.
The generated VM driver also passes Python compilation. Five surface shader variants compile with
glslang, including shared rounding with blur, color management and mirror output.
Package compilation and isolated VM execution remain queued
behind another workstation workload. These checks have not established a
before-and-after runtime result yet. No compositor or browser was activated on
the interactive desktop. Scale, blur, animation, capture, resource-failure and
native browser panel tests in the larger acceptance matrix remain required before
claiming the complete renderer behavior is verified.
