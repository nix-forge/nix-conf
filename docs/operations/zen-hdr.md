# Zen rendering and HDR on the desktop

On September 6, 2026, the Zen HDR workaround was withdrawn after reproducing
black windows and rounded holes inside ordinary web pages. The affected setup
is Zen 1.21.15b / Gecko 154, Hyprland 0.56.0, Ryzen 7700X integrated graphics,
RTX 4070, and ASUS PG32UCWM on DP-4 at 3840×2160 with scale 1.5.

The desktop configuration explicitly sets `gfx.color_management.hdr` and
`gfx.color_management.hdr.force_enabled` to false. Explicit false values reset
existing profiles that previously enabled the trial. Zen uses its normal GPU
selection; the AMD-specific `DRI_PRIME`, `MOZ_DRM_DEVICE`, and
`__EGL_VENDOR_LIBRARY_FILENAMES` launcher overrides have been removed.
Hyprland's monitor HDR configuration remains available to other applications.

## Diagnosis

A solid green page reproduced the user's symptoms without YouTube, extensions
from the user's profile, or video decoding. Screenshots captured through grim
showed the defects even though browser-side page execution continued normally.

| Renderer | HDR preferences | Ordinary page result |
| --- | --- | --- |
| Forced AMD, displayed through NVIDIA | Enabled | Black window and rounded tile cutouts |
| Forced AMD, displayed through NVIDIA | Disabled | Black window, cutouts gone |
| Normal GPU selection | Enabled | Page visible, rounded tile cutouts remain |
| Normal GPU selection | Disabled | Solid page through scrolling and resizing |

The first HDR check had a critical coverage gap. It verified the physical
connector switching to PQ and advancing video frames, but did not inspect
ordinary desktop rendering. That allowed the broken configuration to pass.
Fullscreen video metadata and frame counters alone do not establish a usable
browser or prove that all decoded frames are visibly correct.

The earlier AMD trial did produce EOTF 2 on the physical connector in fullscreen
and return to EOTF 0 afterward. NVIDIA rendering with the HDR preferences alone
restored YouTube's HDR choices but did not produce real HDR output in that trial.
Mozilla tracks a related NVIDIA software-frame upload limitation in
[bug 2012285](https://bugzilla.mozilla.org/show_bug.cgi?id=2012285).
The NVIDIA VA-API driver also refused to initialize inside the decoder sandbox.
The repair does not weaken the sandbox or force hardware decoding.

## Rendering regression check

`tests/browsers/check_hdr_output.py --rendering-only` opens an isolated profile,
maximizes a solid page, scrolls it, and resizes the window. It captures the actual
Hyprland output with grim and requires every sampled interior pixel to remain
green. The activated HDR trial failed all three stages with 3,504,384 incorrect
interior pixels per capture. The repaired build passed all three with zero.
Black output and rounded holes both fail. It saves three screenshots and
`rendering.json`. It does not access existing tabs, cookies, or history.

Run from the repository on the desktop's visible Hyprland session:

```sh
nix shell --impure --expr '
  let pkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux;
  in [ pkgs.geckodriver pkgs.grim
       (pkgs.python3.withPackages (p: [ p.selenium p.pillow ])) ]
' --command python3 tests/browsers/check_hdr_output.py \
  --rendering-only \
  --user-js "$HOME/.config/zen/default/user.js" \
  --output /tmp/zen-rendering-check
```

Use `--browser /path/to/zen-beta` and a corresponding `--user-js` to test a built
configuration before activation. The check briefly manipulates its own visible
window. Keep that test window focused while it runs.

## Future HDR trials

Without `--rendering-only`, the check now requires the rendering check to pass
before testing the local 10-bit 4K60 VP9 PQ fixture. This mode also needs FFmpeg,
ffprobe, and modetest from `pkgs.ffmpeg` and `pkgs.libdrm.bin`. It is expected to
fail with the current SDR browser configuration. Do not use it to justify
re-enabling HDR unless ordinary rendering and visible video playback both work.

The HDR portion reads `HDR_OUTPUT_METADATA` directly from the NVIDIA DRM
connector. EOTF 2 means ST 2084 PQ HDR; EOTF 0 or absent metadata means SDR.
Hyprland's `colorManagementPreset` describes the configured preset, not the
active signal. Neither metadata nor screenshots measure panel luminance or
replace display calibration.
