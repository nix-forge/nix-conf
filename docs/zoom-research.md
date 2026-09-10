# Zoom on NixOS with Hyprland

Reviewed: 2026-09-09. Scope: Zoom Workplace 7.1.5.4332 on x86_64 Linux,
nixpkgs `0968519e14f7aa7d3e9b389682bd74d2b51c8ce8`, Hyprland
`ee0409623e2d6a683374b39a32e0ac3d087841aa`, and
xdg-desktop-portal-hyprland `ba31964ee42b56bcb0d3b78a64ead5d8a1c3c6f6`.

## Answer

Use the upstream NixOS `programs.zoom-us.enable` module for the integrated
desktop. It supplies Zoom's FHS environment with the portal packages selected
by the system. Installing bare `pkgs.zoom-us` leaves every portal-support flag
disabled by default. The existing Hyprland, PipeWire, and WirePlumber services
do not compensate for missing packages inside that environment. This is a
packaging integration defect, identified by comparing the installed FHS tree
with the pinned [package recipe][package] and [NixOS module][module].

Keep the existing media stack and start with Zoom's native Wayland behavior.
Use its PipeWire capture option when selecting the screen-sharing backend.
Verify the transmitted result in a meeting before calling the setup complete.
Neither successful evaluation nor an active portal service proves that another
participant receives usable audio and video.

## Findings and sources

### Packaging and desktop integration

The pinned NixOS Zoom module detects Hyprland, the PulseAudio-compatible
PipeWire service, and the configured portal packages. It passes those into
the Zoom package and installs the resulting application. Its package already
contains PipeWire libraries and the Wayland dependencies. There is no need for
a separate PulseAudio daemon. Avoid installing a second unconfigured Zoom
through Home Manager, where its launcher could take precedence. These are
direct observations of the pinned [module][module] and [package][package].

The repository's [Hyprland module](../modules/nixos/desktop-envs/hyprland.nix)
already assigns portal ownership to NixOS and enables UWSM for session
activation. It selects the Hyprland backend with GTK fallback. Keep the
portal package from the Hyprland flake; [XDPH's pinned README][xdph-readme]
specifically recommends that source to maintain compatible dependencies.

### Screen sharing and image quality

The installed Zoom executable contains the setting label `Screen capture
mode on Wayland` and separate `Pipewire Mode` and `Pipewire Mode (Remote
Control)` choices. It also contains corresponding `WaylandShareMode` enum
names. This establishes that the client has those controls, but does not
establish a supported `zoomus.conf` key or numeric value. The legacy
`enableWaylandShare` string was absent from that executable. Do not add
guessed configuration keys based on old workaround posts. Use the current
client's settings UI and inspect the resulting behavior.

Zoom's [screen-sharing guide][share] still describes Wayland sharing as
limited to a whole desktop or whiteboard. In contrast, the pinned
[Hyprland portal implementation][screencopy] explicitly handles monitor,
window, and region capture. Treat these as distinct claims. The portal can
capture a window, but that alone does not prove this Zoom version offers or
successfully transmits it. Test each needed mode. Remote control is a separate
portal capability and needs its own acceptance test.

Leave video optimization off for text, code, and slides. Zoom warns that its
video-clip optimization can blur ordinary shared content. Enable it when
sharing motion video and turn it off afterward. A high-refresh 4K desktop
does not imply that Zoom transmits 4K at the monitor's refresh rate. Inspect
the receiver's result and meeting statistics. [Zoom screen-sharing guide][share]

The client [release notes][releases] document fixes for Wayland sharing,
Linux sharing crashes, and black output on later sharing attempts within
one meeting. A useful regression test therefore includes stopping and
starting sharing at least three times, as well as reopening the client.

### Audio and camera

Zoom officially supports sharing computer sound on Linux, with mono and
stereo choices. Use the `Share Sound` control for presentation audio; the
microphone alone does not represent computer-sound sharing.
[Zoom computer-audio guide][computer-audio]

The existing [desktop audio policy](../hosts/nixos/desktop/local/audio.nix)
uses a 48 kHz graph, a 512-frame default quantum, and RTKit ordering. Its
Bluetooth policy retains A2DP playback and leaves headset profile switching
under manual control. Keep that previously tested policy. For meetings with
Bluetooth headphones, the separate microphone avoids switching playback to
the headset profile. The earlier [audio investigation](linux-audio-load-cutout-research.md)
records why those buffering and scheduling choices exist.

Zoom provides speaker and microphone tests and a camera preview. Its normal
microphone processing uses noise suppression and echo cancellation; its
music mode disables noise suppression. Keep the normal speech path for
ordinary meetings and use music processing only when appropriate.
[Zoom client settings][settings], [advanced audio settings][audio]

The [webcam configuration](../hosts/nixos/desktop/local/webcam.nix) identifies
a Brio 101 and records 1080p30 MJPEG capability, with only 5 fps at uncompressed
1080p. Let the application negotiate the capture format. Zoom's HD toggle
does not guarantee transmitted 1080p; Zoom documents plan and bandwidth
requirements. Check the camera preview and the actual sent resolution.
[Zoom video-quality guide][video]

### GPU acceleration and fractional scaling

The [graphics configuration](../hosts/nixos/desktop/local/hardware/graphics.nix)
uses an RTX 4070 for the desktop and keeps the AMD integrated GPU available.
The [display configuration](../homes/desktop/local/hyprland.nix) uses 1.5
scaling at 3840 by 2160. Keep the existing Qt Wayland selection and automatic
application scaling as the initial configuration. An XWayland workaround
needs a demonstrated rendering or capture failure before it becomes policy.

Zoom documents Linux hardware acceleration for receiving video, but warns
that inappropriate acceleration settings can worsen the picture.
The NVIDIA VA-API driver's own documentation says it supports decoding,
not encoding, and primarily targets Firefox. Its presence does not prove
Zoom uses NVENC or NVDEC. Keep Zoom's defaults until a meeting test shows
which path works. Do not force a global VA-API driver on this mixed-GPU
system. [Zoom advanced video settings][advanced-video],
[NVIDIA VA-API driver][nvidia-vaapi]

### Following the system's dark appearance

As of September 9, 2026, Zoom's official latest Linux archive endpoint
redirected to `7.1.5.4332`. Both Nixpkgs `master` and `nixos-unstable` also
packaged that version, matching this repository's pinned package. The
Workplace release notes list 7.1.5 for Linux on July 20; the later 7.1.8
entry does not include Linux. The upcoming-release section gives no date
for 7.2.0. There is no observed Nixpkgs delay for Linux 7.2.0 at this check.
[Linux download][linux-download], [release notes][releases],
[Nixpkgs master][package-master], [NixOS unstable][package-unstable]

The desktop already exports `prefer-dark` through GSettings and returns
`uint32 1` from the appearance portal's `color-scheme` setting. Zoom
7.1.5.4332 nevertheless renders its light interface. Its General settings
show an Appearance section without a color-mode selector. The executable
contains Light, Dark, and System setting labels, but they are not exposed
as usable controls in this Linux release.

The general [settings guide][settings] groups Linux with the other desktop
platforms when describing color modes. The version-specific evidence is
more precise. On September 7, 2026, a Zoom employee said Linux dark mode is
planned for 7.2.0 in response to a report about exactly 7.1.5.4332.
[Zoom employee response][linux-dark-mode]

Keep the system appearance preference in place and recheck the actual
Linux settings when 7.2.0 becomes available. Automatic following still
needs verification in that release. The legacy `useSystemTheme` setting
has no verified connection to the newer color-mode controls, so it was
left unchanged.

### Configuration files and the quality baseline

Zoom documents selected Linux settings under `[General]` in
`~/.config/zoomus.conf`, with instructions to quit the application before
editing and relaunch afterward. Its logging guide is one explicit example.
That does not establish a complete public schema for all client settings.
No supported dark-mode or PipeWire capture-mode key was found. Keep the
file writable and preserve account state; use the actual UI for settings
without a verified file mapping. A read-only Home Manager replacement for
the whole file would interfere with application-owned preferences.
[Zoom's Linux configuration instructions][linux-config]

The installed client's settings were inspected directly after allowing the
video page to finish loading. The following existing choices suit ordinary
spoken meetings on this desktop; they did not require additional changes.

| Setting | Observed value |
| --- | --- |
| Speaker | AirPods playback |
| Microphone | Brio 101 Mono |
| Automatic microphone volume | Enabled |
| Audio processing | Noise removal, suppression set to Auto |
| Original sound for musicians | Disabled |
| Camera | Brio 101, HD enabled |
| Touch up appearance and software low-light adjustment | Disabled |
| Forced TCP screen sharing | Disabled |
| Explicit screen-share frame-rate cap | Disabled |

HD is a client preference, not a promise of transmitted 1080p. Keep the
previously selected PipeWire capture mode and automatic scaling. Use
video-clip optimization only for motion content, and enable Share Sound
when the presentation needs computer audio. Leave hardware acceleration
at the client defaults until a reproducible problem justifies changing it.

## Validation and limits

The implementation built Zoom and the complete desktop system on the
`desktop` host. The configured Zoom FHS tree contains the Hyprland and GTK
portal metadata that the previous package lacked. Home Manager evaluation
confirms it no longer adds a second Zoom package and registers `zoommtg`,
`zoomus`, and Zoom invitation files with `Zoom.desktop`. Formatting and
focused Nix checks passed.

The corrected application opened in the active Hyprland session as a native
Wayland window. PipeWire, its PulseAudio compatibility service, WirePlumber,
and both portal services were active. The portal advertised monitor, window,
and virtual source types, plus hidden and embedded cursor modes. These
capabilities do not establish which choices Zoom exposes successfully.

A local camera test discarded 300 MJPEG frames at 1920 by 1080. Capture
settled at approximately 29.94 fps after startup. A shorter FFmpeg test
completed but emitted duplicate-timestamp warnings. A microphone stream
opened through PipeWire and ran for five seconds with output discarded.
These tests retained no camera or microphone recording. They establish
device access and sustained camera capture, not perceived call quality.

In the running client, Settings, Share screen, Advanced offered Auto,
Original, Pipewire, and Pipewire with Remote Control modes. The client was
set to `Pipewire Mode` through its own UI, and the selected combo-box text
was read back. This closes the capture-mode configuration gap; transmitting
and repeatedly restarting a screen share still requires a meeting test.

The corrected package was installed in the user's Nix profile as `zoom` so
the launcher works before system activation. The full desktop build was
not activated because the working tree includes unrelated pending storage
changes. After activating a desktop generation containing
`programs.zoom-us.enable`, run `nix profile remove zoom` to let the
system-managed package own future updates. Until then, the temporary profile
entry stays at the tested version. Existing Zoom URI associations already
resolved to `Zoom.desktop`; their declarative definitions apply on the next
Home Manager activation.

Research checked the pinned Nixpkgs source, installed Zoom launcher and FHS
tree, selected strings in the installed executable, and the repository's
media and display configuration on Linux. These checks established the
installed version and missing portal integration. Binary strings establish
the presence of labels, not runtime behavior or configuration semantics.

An initial Git-filtered desktop evaluation failed because an unrelated
untracked storage module was absent. A path-flake evaluation including the
working tree succeeded during the accompanying implementation task. This
distinction matters when validating a checkout containing untracked modules.

This research did not join a meeting, transmit camera or microphone data,
measure received screen quality, or establish hardware codec use. The
implementation task must record its own build, activation, and runtime
results. The old Zoom Wayland-specific support link returned a 404 during
retrieval; the general sharing guide and installed client supplied the
available evidence instead.

## Implication for this repository

Enable the upstream NixOS Zoom integration and make Home Manager defer to
the system-owned package. Preserve application-managed settings, account
state, the existing webcam policy, and the tested audio stack. Validate a
monitor share, a window share if offered, repeated sharing, computer sound,
microphone playback, and camera motion in the active Hyprland session.

[package]: https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/by-name/zo/zoom-us/package.nix
[module]: https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/nixos/modules/programs/zoom-us.nix
[xdph-readme]: https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/ba31964ee42b56bcb0d3b78a64ead5d8a1c3c6f6/README.md
[screencopy]: https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/ba31964ee42b56bcb0d3b78a64ead5d8a1c3c6f6/src/portals/Screencopy.cpp
[share]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060596
[computer-audio]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063608
[settings]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060612
[audio]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0066398
[video]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060352
[advanced-video]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0066515
[nvidia-vaapi]: https://github.com/elFarto/nvidia-vaapi-driver
[releases]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222
[linux-dark-mode]: https://community.zoom.com/hub-14/zoom-workplace-for-linux-version-7-1-5-4332-81674
[linux-download]: https://zoom.us/client/latest/zoom_x86_64.pkg.tar.xz
[package-master]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/zo/zoom-us/package.nix
[package-unstable]: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/zo/zoom-us/package.nix
[linux-config]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060047
