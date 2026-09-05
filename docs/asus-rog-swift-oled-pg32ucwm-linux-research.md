# ASUS ROG Swift OLED PG32UCWM on the NixOS desktop

Research date: 2026-09-03

## Recommendation

Use DisplayPort from the RTX 4070 to the PG32UCWM. Run the normal desktop at 3840x2160, 240 Hz, 10 bpc, and 1.5 scale. Enable DSC in the monitor because this GPU has DisplayPort 1.4a rather than the monitor's DisplayPort 2.1 UHBR20 link. Enable VRR in the monitor, then limit it to fullscreen content in Hyprland. Keep the ordinary desktop SDR or color-managed wide gamut and let Hyprland switch to HDR for clients that declare HDR content.

Treat 1920x1080 at 480 Hz as a separate, on-demand competitive gaming profile. It replaces the 4K mode; it is not an additional capability that can be active at the same time.

The first physical setup should use these monitor OSD settings:

1. `System Setup > Power Setting > Performance Mode`
2. `System Setup > DisplayPort Stream > DisplayPort 1.4`
3. `System Setup > DSC Support > On`
4. `Gaming > Variable Refresh Rate > On`
5. `Gaming > Frame Rate Boost > Off` for 4K/240 Hz
6. `System Setup > OSD Setup > DDC/CI > On`

The first four are necessary for the intended 4K/240 Hz, HDR, and VRR path. ASUS says Performance Mode is required to enable the monitor's functions. The DisplayPort 1.4 choice must match the RTX 4070, while DSC makes the link bandwidth sufficient.

## What the monitor can do

ASUS specifies the following hardware and signal capabilities in the [product overview](https://rog.asus.com/us/monitors/27-to-31-5-inches/rog-swift-oled-pg32ucwm/), [full specifications](https://rog.asus.com/monitors/27-to-31-5-inches/rog-swift-oled-pg32ucwm/spec/), and [English user guide](https://dlcdnets.asus.com/pub/ASUS/LCD%20Monitors/PG32UCWM/ASUS_PG32UCWM_EN.pdf):

| Area | Capability |
| --- | --- |
| Panel | 31.5-inch Tandem RGB OLED, 3840x2160, true RGB stripe, 0.03 ms GTG |
| Native mode | 3840x2160 at up to 240 Hz |
| Frame Rate Boost | 1920x1080 at up to 480 Hz |
| VRR | 48 to 240 Hz in native mode; 48 to 480 Hz with Frame Rate Boost |
| Adaptive sync | NVIDIA G-SYNC Compatible and AMD FreeSync Premium Pro |
| Color | True 10-bit, 1.07 billion colors, 99% DCI-P3, factory Delta E below 2 |
| HDR | HDR10, Dolby Vision, VESA DisplayHDR 400 True Black, 1,000 cd/m² claimed peak |
| DisplayPort | DisplayPort 2.1a UHBR20, full 80 Gbit/s |
| HDMI | Two HDMI 2.1 FRL inputs, 48 Gbit/s each |
| USB-C | DisplayPort Alt Mode and up to 90 W power delivery |
| USB hub | Three USB 3.2 Gen 1 Type-A ports and one USB-B upstream port |
| Other | KVM, DDC/CI, 3.5 mm headphone output, no speakers |

The manual's timing table exposes 4K modes at 60, 95, 120, 144, and 240 Hz over both HDMI and DP/USB-C. With Frame Rate Boost on, it exposes 1080p at 60, 120, 240, 280, 360, and 480 Hz. The table also lists 24.5-inch, 27-inch, and square simulation timings. These simulation modes disable VRR, so they are poor defaults for this desktop.

The display does not offer every advertised feature at once:

- Frame Rate Boost changes the signal mode from 4K/240 Hz to 1080p/480 Hz.
- ELMB and VRR cannot be active together. HDR also disables ELMB. On this OLED, VRR is the better general gaming choice.
- PIP/PBP disables VRR, HDR, DSC, and Frame Rate Boost.
- Aspect-ratio simulation disables VRR.
- OLED Anti-Flicker works only on DisplayPort and only over a restricted refresh range.

## Link bandwidth and the RTX 4070

The monitor's UHBR20 input is ahead of this computer's GPU. ASUS advertises uncompressed 4K/240 Hz only over its 80 Gbit/s DisplayPort 2.1a path. [NVIDIA's RTX 4070 specifications](https://www.nvidia.com/en-us/geforce/graphics-cards/40-series/rtx-4070-family/) list DisplayPort 1.4a and say that 4K/240 Hz HDR uses DSC. NVIDIA also lists HDMI 2.1 with DSC for 4K/240 Hz.

This means:

- Use the supplied DP80 cable if the US package contains it. ASUS says accessories vary by region, so verify the box rather than assuming. A certified DP80 cable is backward compatible with the RTX 4070's HBR3 link.
- Select DisplayPort 1.4 in the monitor OSD and enable DSC. Selecting DisplayPort 2.1 cannot add capability to a DisplayPort 1.4a source.
- No special NVIDIA DSC switch should be required. NVIDIA's Linux driver team says DSC has long been supported and that very high pixel-clock modes work by default from driver 535.43.02 onward in its [open kernel module discussion](https://github.com/NVIDIA/open-gpu-kernel-modules/discussions/238). This configuration evaluates to driver 595.91.07.
- HDMI 2.1 is a workable fallback, but it still needs DSC for this mode. DisplayPort is preferable because OLED Anti-Flicker is DP-only and the intended OSD link setting is explicit.
- A future UHBR20-capable GPU can use `DisplayPort 2.1 (20G)` with a DP80 cable and DSC off for ASUS's advertised uncompressed 4K/240 Hz path.

DSC is visually lossless transport compression, not a reduction in render resolution. The GPU still renders and the monitor still receives a 3840x2160, 240 Hz timing.

## Repository findings

The desktop is a NixOS Hyprland/UWSM workstation driven by an RTX 4070. Relevant configuration lives in:

- [`hosts/nixos/desktop/local/hardware/graphics.nix`](../hosts/nixos/desktop/local/hardware/graphics.nix)
- [`homes/desktop/local/hyprland.nix`](../homes/desktop/local/hyprland.nix)
- [`modules/home/desktop/hdr.nix`](../modules/home/desktop/hdr.nix)
- [`modules/home/desktop/noctalia.nix`](../modules/home/desktop/noctalia.nix)
- [`hosts/nixos/desktop/local/headless-remote-play.nix`](../hosts/nixos/desktop/local/headless-remote-play.nix)
- [`modules/nixos/gaming/gamescope.nix`](../modules/nixos/gaming/gamescope.nix)

Evaluation of the current flake produced:

| Component | Version or state |
| --- | --- |
| Hyprland | 0.56.2 |
| NVIDIA driver | 595.91.07, production branch |
| NVIDIA kernel module | Open module, DRM modesetting enabled |
| Linux | 7.2 |
| Gamescope | 3.16.25 |
| mpv | 0.41.0 |
| ddcutil | 2.2.7 |

The GPU and driver foundation is already appropriate for Wayland. The old display setup was built around a synthetic `SUNSHINE` output at 2562x1656/120 and globally disabled VRR. An HDR module existed but was not enabled. Its original `render:cm_fs_passthrough` setting is invalid on the current compositor: [Hyprland 0.55 removed that option](https://github.com/hyprwm/Hyprland/releases/tag/v0.55.0) and made the behavior automatic through `render:cm_auto_hdr`.

The PG32UCWM's 696.58 by 391.82 mm visible area and 3840x2160 raster are about 140 PPI. The repository's 96 DPI reference produces a target scale of 1.46, so its conventional-scale resolver correctly selects 1.5. This yields an exact 2560x1440 logical desktop and a 24-pixel cursor from the configured 16-pixel logical size.

## Hyprland target

The physical monitor rule should eventually resolve to these values:

| Field | Recommended value | Reason |
| --- | --- | --- |
| Output | Actual connector or verified `desc:` prefix | Do not assume the EDID description before the monitor is attached |
| Mode | `3840x2160@240` | Native panel resolution and maximum native refresh |
| Scale | `1.5` | About 140 PPI; exact 2560x1440 logical result |
| Bit depth | `10` | Native panel depth and better color-management precision |
| Color preset | `auto` initially | Hyprland's recommended preset, sRGB at 8 bpc and wide color at 10 bpc |
| HDR detection | EDID first; force support only if detection fails | Avoid hiding a cable, EDID, or driver problem |
| VRR | `2` initially | Fullscreen-only VRR works without relying on app content-type metadata |
| Automatic HDR | `render:cm_auto_hdr = 1` | Switches fullscreen declared HDR content to BT.2020/PQ |

[Hyprland's monitor documentation](https://wiki.hypr.land/0.56.0/Configuring/Basics/Monitors/) recommends 10 bpc for color-space handling, describes `auto` as the recommended color preset, and warns that some applications cannot capture a 10-bit output. Its [configuration reference](https://wiki.hypr.land/configuring/core/config-options/) defines VRR mode 2 as fullscreen-only and mode 3 as fullscreen only when the client supplies `video` or `game` content type.

Mode 3 is a good later refinement if Gamescope and every important native game are verified to send the content type. Mode 2 is the safer first configuration because an untagged fullscreen game still gets adaptive sync. Both avoid variable refresh on the ordinary desktop, where OLED VRR brightness fluctuation is most visible.

If `cm = auto` produces an unwanted wide-gamut desktop, use `cm = srgb` and select sRGB in the monitor OSD. Hyprland can still switch a fullscreen HDR client when `cm_auto_hdr` is enabled. Keep the compositor and monitor color-space choices paired: `srgb` with the monitor's sRGB mode, or `auto`/`wide` with the monitor's Wide Gamut mode. Do not install the generic ASUS ICC as an always-on workaround. Hyprland says an ICC profile overrides the color preset and is fundamentally incompatible with HDR gaming. A measured per-unit ICC belongs in a separate SDR color-critical profile.

Hyprland still labels its `hdr` and `hdredid` presets experimental. Keep HDR automatic and scoped to the physical output. If a capture application fails with 10 bpc, test it at 8 bpc before changing the whole desktop.

## HDR applications

The kernel does not turn HDR on by itself. Its [DRM/KMS documentation](https://docs.kernel.org/gpu/drm-kms.html) says userspace must read the display EDID, decide the composition and tone-mapping policy, and send `HDR_OUTPUT_METADATA` and colorspace information to the driver. Hyprland is that userspace component here.

For video, mpv 0.41 needs `--target-colorspace-hint-mode=source` for Hyprland's fullscreen automatic HDR path. Hyprland calls this out in its current configuration reference. The repository's mpv module did not set the option before this monitor work.

For Proton games that need nested Gamescope, enable the NixOS Gamescope WSI layer and use the HDR option per game. Before this monitor work, the configuration evaluated `programs.gamescope.enableWsi` to false. Gamescope's own `--help` source says [`--hdr-enabled` requires the Gamescope WSI layer](https://github.com/ValveSoftware/gamescope/blob/master/src/main.cpp). Do not force HDR globally because SDR-only games then need unnecessary conversion.

Dolby Vision is a monitor capability, not a proven capability of this Linux session. The documented Hyprland path uses HDR PQ/BT.2020, the upstream [Wayland color-management protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/color-management/color-management-v1.xml) describes ST 2084 PQ and HLG, and the documented DRM property carries HDR output metadata. None of those sources describes a Dolby Vision output path. The practical expectation on Hyprland is HDR10. Dolby Vision may still be useful for a separate console, streaming device, macOS, or Windows input.

For HDR10 games, start with the monitor's `Gaming HDR` preset. `DisplayHDR 400 True Black` is the certification-oriented alternative. Calibrate each game's paper white and peak slider against visible clipping; ASUS labels 1,000 nits as peak brightness, not sustained full-screen luminance.

## DDC/CI, USB, and KVM

Connect the RTX 4070 over DisplayPort and also connect the monitor's USB-B upstream cable to the desktop. The DisplayPort cable carries video and DDC/CI, while USB-B makes the hub, keyboard, mouse, and KVM available to the desktop. Set the hub to remain available during standby if wake-by-keyboard or wake-by-mouse must work through the monitor.

Reserve USB-C for a laptop or another system. ASUS says `USB 3.2` Type-C bandwidth mode caps display input at 3840x2160/120. A USB-C source that needs more video bandwidth must use the monitor's USB 2.0 bandwidth mode, sacrificing SuperSpeed data lanes. Smart KVM automatically enables PBP and USB-C, which also disables the primary gaming features. Use ordinary input-to-upstream KVM mapping for a 4K/240 desktop.

Noctalia's [brightness service](https://docs.noctalia.dev/noctalia/services/brightness/) makes ddcutil opt-in for external displays. The correct sequence after connection is:

```console
ddcutil detect --brief
ddcutil capabilities --display <number>
ddcutil getvcp 10 --display <number>
```

Only enable the Noctalia ddcutil backend after those commands identify the PG32UCWM and VCP feature `0x10` works. In HDR modes, ASUS disables ordinary brightness control except under Adjustable HDR, so a DDC brightness slider may be unavailable or ineffective while HDR is active.

[ddcutil requires](https://www.ddcutil.com/config_steps/) the `i2c-dev` kernel module and user read/write access to the GPU's I2C buses. The pinned NixOS [hardware.i2c module](https://github.com/NixOS/nixpkgs/blob/9fbb54b33e91ee4ca368e35a78e0613c720600b3/nixos/modules/hardware/i2c.nix) provides `i2c-dev` and active-seat `uaccess`, so permanent membership in the broad `i2c` group is unnecessary. If detection fails, run `ddcutil environment` before changing NVIDIA settings. ddcutil documents an [undocumented NVIDIA I2C workaround](https://www.ddcutil.com/nvidia/), but it should be a last resort applied only after a reproduced failure.

ASUS DisplayWidget Center and ASUS Display Control CLI are not Linux tools. ASUS provides [DisplayWidget Center for Windows 11 and macOS 12 or later](https://www.asus.com/content/monitor-software-osd-displaywidgetcenter/), while the [official CLI repository](https://github.com/ASUS-Display/asus-display-control) publishes only Windows and macOS binaries. Use the physical OSD and standard DDC/CI controls on NixOS.

## Firmware and OLED care

The current ASUS release is [firmware MCM102, dated 2026-07-15](https://rog.asus.com/monitors/27-to-31-5-inches/rog-swift-oled-pg32ucwm/helpdesk_bios/). It fixes three Dolby Vision problems and an LED status warning. Check `System Setup > Information` before updating because a newly shipped monitor may already contain it.

The official MCM102 package includes a Linux-independent USB flash-drive update:

1. Format a USB drive as FAT32.
2. Copy `PG32UCWM.bin` to it without renaming the file.
3. Insert the drive into the monitor and disconnect the USB-B upstream cable.
4. Hold the monitor control button for five seconds.
5. Leave power connected until the update finishes and the monitor restarts.

The package checksum published by ASUS is SHA-256 `208814aa3db32cd1752512786bc61f0b44776e6136a8b808362695676a31e5b7`.

For panel care:

- Leave pixel cleaning automatic. It runs after the monitor is switched off, takes about six minutes, and is interrupted by removing power or turning the monitor back on.
- Keep Screen Move, screen dimming, outer dimming, global dimming, and logo/taskbar detection enabled unless one causes a specific problem.
- Use Uniform Brightness with the monitor's sRGB mode for stable SDR desktop luminance. ASUS says this combination reduces visible automatic brightness changes as white-window size changes.
- The existing Hypridle policy locks after five minutes, turns DPMS off after five and a half minutes, and suspends after fifteen minutes. This is already strong protection for static desktop use.
- The Neo Proximity Sensor can add protection. ASUS specifically warns that near-static activity can make it blank the display, so start with high motion sensitivity and a long timer. Disable it if coding causes false blanking; Hypridle still protects the panel.

## Removing the virtual display

Once the physical output is present, remove the `SUNSHINE` monitor rule and the service that creates the virtual output. Remove the Noctalia exception that hides brightness for `SUNSHINE`. These changes are independent of keeping Sunshine itself.

Without the virtual output, Sunshine can capture the physical desktop, but remote access depends on the PG32UCWM remaining logically connected. If the monitor is unplugged or its standby behavior makes the DP connector disappear, a headless Moonlight session will no longer have a capture target. Keep a virtual-output fallback only if unattended remote access with the monitor disconnected matters.

## Arrival-day validation

Do not hard-code the expected EDID description until the monitor is attached. On the desktop host:

1. Connect DP and USB-B, apply the OSD settings above, and reboot or restart the session.
2. Run `hyprctl monitors all`. Record the real connector and `description`, then confirm 3840x2160 at 240 Hz, scale 1.5, and 10 bpc.
3. Confirm the monitor OSD reports 3840x2160/240 and VRR when a fullscreen game runs.
4. Run the three ddcutil commands above before enabling shell brightness control.
5. Test one native SDR application, one HDR video, and one HDR game. Confirm the OSD changes to HDR only for declared HDR content and returns to the normal color mode afterward.
6. Test screen sharing and Sunshine once with 10 bpc enabled.
7. Turn on Frame Rate Boost and confirm 1920x1080/480 only when that lower-resolution profile is wanted, then return it to off for the normal 4K desktop.

If 4K/240 is absent, check the OSD's DisplayPort 1.4 and DSC settings and the cable before adding a custom mode. If 10 bpc or HDR is absent, inspect EDID and DRM connector properties before forcing support. If VRR flickers, keep fullscreen-only VRR and try the monitor's DP-only OLED Anti-Flicker range rather than disabling adaptive sync everywhere.
