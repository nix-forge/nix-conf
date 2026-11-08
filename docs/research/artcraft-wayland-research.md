# Native Wayland support for ArtCraft

Reviewed: 2026-10-08. Scope: all twelve revisions pinned by current package recipes.

## Answer

All twelve desktop manifests already explicitly enable `eframe/wayland` and `eframe/x11`. This is mostly activation and validation work for native windows. Complete feature parity needs more work, especially file-manager drag-and-drop and PhotoCraft pen tablets. No GUI rewrite is indicated by the source review.

## Findings and sources

Local observation: all twelve Cargo.lock files pin eframe and egui-winit 0.36.2, winit 0.30.13, rfd 0.17.2, arboard 3.6.1 and smithay-clipboard 0.7.3. Their current recipes, for example [CADCraft](../../pkgs/pkgs/by-name/ca/cadcraft/package.nix), already wrap Wayland and libxkbcommon runtime libraries. [Eframe documentation](https://docs.rs/eframe/0.36.2/eframe/) describes its native Wayland feature.

[Winit 0.30.13 backend selection](https://github.com/rust-windowing/winit/blob/v0.30.13/src/platform_impl/linux/mod.rs#L680-L720) chooses nonempty `WAYLAND_DISPLAY` or `WAYLAND_SOCKET` ahead of `DISPLAY`, unless application code forces a backend. It does not read the old `WINIT_UNIX_BACKEND` variable in this path. CADCraft, EffectCraft, FilmCraft, GridCraft, LightCraft, PdfCraft, PhotoCraft, SoundCraft, VectorCraft and WordCraft use normal Linux selection. The event-loop hooks in EffectCraft and FilmCraft only affect macOS activation behavior.

[DesignCraft](https://github.com/storytold/designcraft/blob/14e677b24216396e398823ff034d9882322362d1/apps/designcraft/src/main.rs) and [DeckCraft](https://github.com/storytold/deckcraft/blob/d0e57d7e25f9852179cc66be12dd6188f1c05535/apps/deckcraft/src/main.rs) deliberately force X11 whenever `DISPLAY` is present, unless `DESIGNCRAFT_WAYLAND` or `DECKCRAFT_WAYLAND` is present. In an existing Wayland session, these opt-ins allow native selection without a rebuild:

```sh
DESIGNCRAFT_WAYLAND=1 designcraft
DECKCRAFT_WAYLAND=1 deckcraft
```

The variables disable the X11 override; they do not themselves force Wayland. Presence matters, rather than parsing a Boolean. `env -u DISPLAY application` in a working Wayland session prevents X11 window selection during a focused smoke test.

DesignCraft's source explains why it prefers XWayland: file-manager drag-and-drop is missing on the current Wayland windowing path. File/Open and import dialogs remain alternatives. Complete drop support calls for shared windowing integration rather than twelve UI rewrites.

[PhotoCraft's tablet crate](https://github.com/storytold/photocraft/blob/e5e3e397523b4db6a016dd19526e4c68514fcc72/crates/tablet/src/lib.rs) explicitly lacks Wayland pressure, tilt, barrel rotation and eraser input. It says `zwp_tablet_v2` must use winit's existing display and surface; binding the protocol stops pointer emulation, so pen motion must enter egui too. [The desktop bridge](https://github.com/storytold/photocraft/blob/e5e3e397523b4db6a016dd19526e4c68514fcc72/apps/photocraft/src/tablet.rs) deliberately avoids XInput2 on native Wayland. Pens paint like a mouse. This is the largest application-specific task.

Ordinary egui text copy/paste has a native path through [smithay-clipboard](https://github.com/emilk/egui/blob/0.36.2/crates/egui-winit/src/clipboard.rs). Image copy uses arboard. [Arboard 3.6.1](https://github.com/1Password/arboard/blob/v3.6.1/README.md) needs `wayland-data-control` and compositor data-control support for its pure Wayland path. [PhotoCraft](https://github.com/storytold/photocraft/blob/e5e3e397523b4db6a016dd19526e4c68514fcc72/apps/photocraft/Cargo.toml) and [VectorCraft](https://github.com/storytold/vectorcraft/blob/c0396c0761f7e58778ba21bb249a8a6f23db99a3/apps/vectorcraft/Cargo.toml) explicitly enable it. [DeckCraft](https://github.com/storytold/deckcraft/blob/d0e57d7e25f9852179cc66be12dd6188f1c05535/apps/deckcraft/Cargo.toml) and [PdfCraft's UI](https://github.com/storytold/pdfcraft/blob/22752dc9157706e55ead60b89a857a9ce03c8fc0/crates/ui-egui/Cargo.toml) enable image data without that option. Their direct image clipboard paths need further feature-graph and runtime checks. Manifest inspection does not prove every resolved Cargo feature. The other eight apps have no direct arboard calls in their Rust source snapshots.

[rfd 0.17.2](https://docs.rs/rfd/0.17.2/rfd/) defaults to XDG portal dialogs. It needs a working FileChooser portal and documents Zenity for message dialogs and fallback. The wlroots portal alone does not implement the required file-dialog API. Test open/save, filters, cancellation and dialog placement on the actual desktop.

IME exists in the framework but this review has not exercised preedit/commit, dead keys, non-US shortcuts, candidate placement or application-specific editors. WordCraft, GridCraft, DesignCraft and VectorCraft warrant focused checks. Scaling, multiple monitors, focus, decorations and GPU presentation also need native compositor validation.

| Applications | Native window activation effort | Main extra validation or implementation |
| --- | --- | --- |
| CADCraft, EffectCraft, FilmCraft, GridCraft, LightCraft, SoundCraft, WordCraft | Already enabled; test normal session | Dialogs, clipboard, file drops, text input and graphics |
| DesignCraft | Set one environment variable | File drops explain the current X11 default |
| DeckCraft | Set one environment variable | File drops and direct image clipboard |
| PdfCraft | Already enabled | Direct image clipboard and dialogs |
| VectorCraft | Already enabled | Compositor support for image clipboard and text input |
| PhotoCraft | Already enabled | Native tablet integration is missing; image clipboard and file drops |

## Validation and limits

Read pinned upstream Cargo manifests and Cargo.lock files for all twelve apps. Inspected source at matching locked framework versions. Read current packaging recipes. No build, launch or interactive native Wayland test ran. [Existing GUI checks](../../pkgs/flake/dev/artcraft.nix) explicitly unset `WAYLAND_DISPLAY` and use Xvfb; their passes establish X11 smoke coverage only.

## Implication for this repository

Add a separate compositor-based check with `DISPLAY` unavailable and the DesignCraft/DeckCraft opt-ins set. Validate twelve windows, open/save and text/image copy/paste, then application-specific interactions. Preserve existing X11 compatibility while measuring native behavior.

Effort estimates are judgments based on source scope. Setting the opt-ins takes minutes. Packaging preferences and automated compositor smoke checks could take hours to one day. File drops and robust image clipboard parity likely require several engineering days. PhotoCraft tablet integration plus hardware/compositor coverage could take one to several weeks. Rebuild time and graphics-driver bugs can extend these estimates.
