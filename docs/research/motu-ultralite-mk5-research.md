# MOTU UltraLite-mk5 on the NixOS desktop

Reviewed: 2026-10-12. Scope: UltraLite-mk5, mixed desktop playback, games,
calls, and occasional recording. The initial research preceded hardware arrival;
the commissioning results below record the subsequent live inspection.

## Answer

Keep the existing PipeWire baseline. The desktop already has the standard USB
audio driver and working realtime audio threads. Full readiness still depends
on authorizing the actual USB device, verifying its channel layout, and choosing
a tested mixer-control path. Linux audio support alone does not establish full
CueMix or firmware-update support.

Use 48 kHz with a 512-frame default quantum. Provide a stereo speaker output,
headphone routing, and a dedicated mono microphone source. Keep desktop-loopback
capture separate from the call microphone. Defer device-specific rules until the
hardware supplies its actual descriptors and PipeWire properties.

## Findings and sources

### Device capabilities and control boundary

MOTU documents class-compliant USB audio, 18 physical inputs and 22 outputs at
base rates, 24-bit conversion, independent headphone output, onboard mixing,
EQ, compression, reverb, and loopback. ADAT capacity falls at 88.2/96 kHz.
At 176.4/192 kHz, ADAT, S/PDIF, input effects and reverb become unavailable.
The default loopback occupies host inputs 9-10, with an option to move it to
1-2. Host channels must therefore be checked against the active configuration.
The physical I/O count is not a reliable host-channel map.
[MOTU user guide, v1.33](https://cdn-data.motu.com/manuals/usb-c-audio/UltraLite-mk5_User_Guide.pdf).

The guide describes CueMix 5 and firmware updating on macOS and Windows,
plus mobile control. A supported Mac or Windows machine is the preferred
initial firmware and preset-management path. Save a known-good preset before
returning to Linux. Do not assume older UltraLite AVB browser-control or driver
instructions apply to this USB model.
[MOTU user guide](https://cdn-data.motu.com/manuals/usb-c-audio/UltraLite-mk5_User_Guide.pdf).

Later firmware adds host-mediated remote control, A/B monitoring, monitor
grouping and talkback. Check official release notes after arrival; the current
download page was unavailable during research, so the latest firmware number
is unverified.
[MOTU firmware announcement](https://cdn-data.motu.com/marketing/motu_products/audio_interfaces/ultralite-mk5/motu-ultralite-mk5-firmware-update-pr.pdf).

### Optional Linux control software

The community integration documents USB Ethernet and WebSocket control on
port 1280. This is a userspace control path, separate from the audio driver.
[Controller README at the reviewed revision](https://github.com/MarkWind85/motu-mk5-linux/blob/bf43e082fb6891cc3fe845e953c7e16ad81c85e4/README.md).

Do not install its automatic integration as the initial desktop setup. The
reviewed router starts twelve loopback processes, forces the global graph rate,
sets the underlying output to 100 percent volume, and maps S/PDIF capture onto
the documented default loopback positions. These behaviors require hardware
verification and conflict with the intended minimal desktop routing.
[Router source](https://github.com/MarkWind85/motu-mk5-linux/blob/bf43e082fb6891cc3fe845e953c7e16ad81c85e4/src/audio/router.rs).
It also restores saved writable settings on connection and accepts discovery
announcements on all IPv4 interfaces. Keep any future controller scoped to the
verified USB control link, with explicit changes instead of automatic restore.
[State source](https://github.com/MarkWind85/motu-mk5-linux/blob/bf43e082fb6891cc3fe845e953c7e16ad81c85e4/src/device/state.rs),
[connection source](https://github.com/MarkWind85/motu-mk5-linux/blob/bf43e082fb6891cc3fe845e953c7e16ad81c85e4/src/device/connection.rs).

A mirrored Linux CueMix binary claims an origin with a MOTU employee, but its
linked provenance, current vendor support and firmware compatibility were not
verified. Treat it as an optional evaluation candidate, not a supported release.
[Mirror README](https://github.com/MarkWind85/com.motu.CueMix5-1.0.0/blob/bb742659d8e6a8870123a7ba24b3f4c4cf2f3cf6/README.md).
The older Node bridge opens a wildcard listener without authentication in its
implementation. Keep remote bridging disabled for this local desktop use.
[Bridge source](https://github.com/jpcarrascal/motu-ultralite-mk5-bridge/blob/main/node/index.js).

These are installation-suitability observations from specific source paths,
not a complete security audit of those projects.

### Drivers and the running desktop

The standard Linux `snd_usb_audio` module supports USB audio-class devices.
Kernel source includes a MOTU vendor rate-validation quirk; the inspected
upstream sources do not identify a separate mk5 driver requirement.
This supports starting with the stock driver, but is not proof of successful
enumeration on a particular firmware revision.
[Linux USB audio quirks at the inspected revision](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/sound/usb/quirks.c),
[device table](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/sound/usb/quirks-table.h),
[implicit feedback source](https://github.com/torvalds/linux/blob/24a19b953e2a3d0ea5a8c4951a0ab8f32720c907/sound/usb/implicit.c).

Local observations on the running desktop:

| Component | Observed state | Decision |
| --- | --- | --- |
| Kernel | `7.2.8-xanmod1` | No replacement justified by this research |
| USB audio | `snd_usb_audio` loaded | Allow normal hotplug binding |
| Driver dependencies | PCM, hwdep, MIDI and core sound modules loaded | No manual dependency list needed |
| USB network drivers | `cdc_ether`, `cdc_ncm`, `rndis_host` available | Bind only the driver matching actual control descriptors |
| PipeWire | 1.6.9, active | Retain |
| WirePlumber | 0.5.18, active | Retain |
| Pulse compatibility | Active | Covers ordinary desktop applications |
| JACK and ALSA compatibility | Enabled in the selected module | Use for recording applications |
| RTKit | Active | Retain the privilege boundary |
| PipeWire processing threads | `SCHED_RR`, priority 20 | Realtime scheduling is working |
| USBGuard | Active, default deny | Enroll the real device before testing audio |
| Volume tools | `pwvucontrol`, `pavucontrol` installed | Use for desktop defaults and stream selection |
| Graph tool | `qpwgraph` absent from command PATH | Recommended optional addition for channel inspection |

The main PipeWire thread uses normal scheduling; the `data-loop.0` threads
are realtime. Checking only process names would miss this distinction.
PipeWire documents realtime processing and RTKit fallback in its
[RT module reference](https://pipewire.pages.freedesktop.org/pipewire/page_module_rt.html).

Declared owners are [the shared sound module](../../modules/nixos/hardware/sound.nix),
[desktop audio policy](../../hosts/nixos/desktop/local/audio.nix),
[hardware configuration](../../hosts/nixos/desktop/local/hardware/platform.nix),
and [USB authorization policy](../../hosts/nixos/desktop/local/security/usbguard.nix).
The existing node rule targets onboard Generic USB Audio, not the MOTU.
There is no need to preload audio modules into the initrd for this peripheral.
Leave `implicit_fb`, `quirk_alias`, descriptor-validation bypasses, and global
USB power changes unset unless this hardware reproduces a specific failure.

### Quality, latency and efficiency

| Setting | Recommended starting value | Reason |
| --- | --- | --- |
| Graph rate | 48,000 Hz | Matches the current game, video and streaming policy |
| Allowed graph rates | `[ 48000 ]` | Avoid rate changes across concurrent desktop workloads |
| Default quantum | 512 frames | 10.67 ms per graph cycle |
| Minimum quantum | 256 frames | 5.33 ms option for occasional software monitoring |
| Maximum quantum | 2048 frames | Retains recovery margin |
| Forced quantum/rate | Unset | Avoid a global lock from a controller or recording application |
| ALSA sample format | Automatic | Inspect negotiated format before adding an override |
| ALSA periods/headroom | Automatic | Let the installed stack handle the USB device |
| Idle suspension | Default initially | Change only for measured resume problems |
| DSP monitoring | Prefer for dry input monitoring | Avoid an unnecessary host monitoring path |

The graph clock and quantum settings are documented in
[PipeWire configuration](https://docs.pipewire.org/page_man_pipewire_conf_5.html).
The quantum figures above are calculations, not measured end-to-end latency.
512 frames causes half as many graph cycles as 256 frames at the same rate.
Smaller buffers reduce latency; they do not increase sample fidelity.
For this workload, moving to 96/192 kHz or a 64-frame global buffer has no
established benefit that offsets the additional processing and reduced margin.
These are workload recommendations, not universal recording requirements.

Most USB devices need batch-aware buffering. Keep the defaults until `pw-top`
and recording tests establish a problem. Do not start with
`api.alsa.disable-batch = true`, tiny periods, or disabled suspension globally.
[WirePlumber ALSA configuration](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html).
ALSA format and hardware-rate negotiation are described in
[PipeWire properties](https://docs.pipewire.org/page_man_pipewire-props_7.html).
A 32-bit transport container does not turn this interface into a 32-bit ADC.
Use 24-bit recording files where the recording application supports them.

For calls, expose the selected microphone input as mono. For listening and
games, expose a normal stereo sink. If the available desktop profiles hide
needed channels, select Pro Audio and create only the useful virtual endpoints
after verifying each channel. PipeWire supports channel selection and virtual
sinks/sources through its
[loopback module](https://docs.pipewire.org/page_module_loopback.html).
`qpwgraph` can inspect and connect the graph; it does not replace CueMix DSP
control. [Upstream qpwgraph](https://github.com/rncbc/qpwgraph).
Run graph and control tools on demand, without adding a permanent tray process
or a separate JACK server merely to use this interface.

### Security and physical safety

USBGuard currently requires explicit device identity, descriptor hash, and
interface or topology binding. A MOTU allow rule cannot be completed before
the real descriptors are available. Inspect all composite functions, including
any control-network interface. Keep the existing default-deny policy and root
administration. Do not add a vendor-wide or audio-class-wide allow rule.
Firmware changes may require reviewing a changed descriptor hash.
[USBGuard rule language](https://usbguard.github.io/documentation/rule-language.html).

Keep RTKit rather than granting all audio applications unrestricted realtime
priority or `CAP_SYS_NICE`. Preserve the current firewall. If a control network
appears, configure only that verified link, without making it a default route,
DNS provider, trusted firewall interface or bridge to the LAN. The desktop
uses systemd-networkd, so distribution instructions built around NetworkManager
must be translated rather than pasted.

Use the supplied power adapter and a reliable direct USB connection first.
Begin with speakers muted and headphone/monitor levels low. Confirm output
routing before playback. Enable phantom power only for equipment that requires
it, and mute before changing cabling or power. Keep loopback disabled in the
call source and avoid routing the captured call mix back into itself.
These are commissioning precautions, not a claim that Linux controls hardware
gain or phantom power automatically.

Keep USB runtime power management unless a test reproduces disconnects or
resume failures. If necessary, use a rule for the verified MOTU device only.
Kernel USB power controls are per-device as well as global.
[Kernel USB power management](https://docs.kernel.org/driver-api/usb/power-management.html).

## First-connection verification

Run inspections before changing profiles or starting playback:

```sh
sudo usbguard list-devices
lsusb
lsusb -t
aplay -l
arecord -l
wpctl status -n
pw-metadata -n settings
pw-top
```

Review the blocked MOTU identity locally and add only its reviewed rule to the
existing declarative policy. Do not replace the policy with a generated list
of all connected devices. Raw USB output can contain serials; keep it private.
Apply the policy through the normal desktop build/activation workflow before
expecting driver binding. The rule must match the device's exact interface set.

Use the actual current object IDs, not examples copied from another system:

```sh
wpctl inspect <MOTU_DEVICE_ID>
pw-cli enum-params <MOTU_DEVICE_ID> EnumProfile
wpctl set-profile <MOTU_DEVICE_ID> <VERIFIED_PROFILE_INDEX>
wpctl status -n
wpctl set-default <MOTU_STEREO_SINK_ID>
wpctl set-default <MOTU_MONO_MIC_SOURCE_ID>
```

`wpctl` profile indices belong to the device, and defaults use sink/source
node IDs. Selecting a default does not create a missing mono source.
Existing streams may need moving in the volume tool or reopening.
[WirePlumber control reference](https://pipewire.pages.freedesktop.org/wireplumber/man/wpctl.html).

Then verify, with output levels kept low:

1. Confirm USB speed and audio/control driver binding. Compare negotiated
   sample format and hardware rate in `pw-cli` and the device's
   `/proc/asound/card*/stream*` and `pcm*/sub*/hw_params` files while active.
2. Test each needed speaker, headphone and microphone path individually.
   Record a short clip and play it back. Map loopback separately. Do not infer
   USB channel positions from connector labels or advertised channel counts.
3. Verify CueMix or an optional reviewed controller can read and change the
   required DSP/routing settings. Confirm the preset survives a power cycle.
4. Play music while gaming or running a representative queued background
   workload. Watch for increasing `pw-top` errors and audible interruptions.
   This research did not run a synthetic stress test.
5. Test a call and confirm only the intended microphone is captured. Check
   direct monitoring for doubling or feedback with software monitoring enabled.
6. Test idle resume, USB reconnect, suspend/resume and a cold boot. Recheck
   realtime data-thread priorities after resume.
7. For software monitoring, try a 256-frame application request without
   changing the global minimum. Revert to 512 if unreliable. Measure round-trip
   latency with a physical loopback if recording timing matters.

## Validation and limits

The review compared the working-tree configuration at root HEAD
`84e37f5d83e1b218ce8c2c843fe3f9ead479b12c` with the live Linux desktop.
Read-only checks confirmed services, available modules, graph settings and
realtime thread priorities. Existing unrelated staged changes were preserved.
No system configuration was changed, rebuilt or activated.

The two-file Markdown check with rumdl and spelling check with typos passed.
Relative links, final newlines and trailing whitespace passed local inspection;
Gitleaks found no leaks in the new note. These small checks ran directly after
canceling their queued runner invocations behind unrelated builds. No heavy
evaluation or build was started.

Hardware enumeration, final channel mapping, DSP compatibility, latency,
load reliability and reconnect behavior remain untested. Those gaps require
the interface. A documentation review cannot certify complete hardware support.

## Implication for this repository

Retain the existing audio baseline. After arrival, add the reviewed USBGuard
identity and, if necessary, a narrowly matched control-network configuration.
Add `pkgs.qpwgraph` to the desktop home profile if a graph editor is desired.
Create only the verified speaker/headphone/microphone endpoints required for
desktop use, with the full underlying channels available for recording.
Any new package recipe belongs in the package repository. Follow
[desktop build placement](../../AGENTS.md) for later configuration changes.

## Live commissioning on 2026-10-12

The connected device enumerated as `07fd:000c` behind a previously unauthorized
USB dock hub. Both verified identities were added to the declarative USBGuard
policy using descriptor hashes and exact interface sets. Temporary live
authorization enabled inspection without disabling USBGuard.

The native `snd_usb_audio` and `cdc_ether` drivers bound successfully at USB
high speed. At 48 kHz the device exposes 22 playback channels and 20 capture
channels, including loopback. The installed ALSA UCM configuration already
provides stereo output pairs and a mono microphone selection. Its default
loopback mapping agrees with the manual; a custom routing daemon is unnecessary.

The user connected headphones only. The USB Phones stereo sink was selected
as the remembered WirePlumber playback default, initially at 20 percent software
volume. The final requested software volume is unity, or 100 percent.
The user confirmed audible playback. The existing webcam remains the call
microphone. Hardware trims, phantom power and DSP presets were preserved.
The playback and capture hardware paths negotiated `S24_3LE` at 48 kHz.
A brief capture probe sent its samples directly to `/dev/null` and retained
no recording. Live graph observations showed zero errors on the active MOTU
playback path, with a 512-frame graph and realtime processing priority 20.
This is a functional check, not a sustained load or round-trip latency test.

The device control transport reported firmware `2.0.1+2555`, internal clock,
48 kHz and both reported clock locks. The control interface is configured
for IPv4 link-local addressing, without DHCP, DNS, a default route, router
advertisements or forwarding. A stable `motu-control` name scopes UDP discovery
permission to this USB interface. A bound userspace socket received discovery,
and a direct WebSocket connection read device state. No remote bridge or
automatic settings writer was installed. The latest supported firmware still
needs comparison with MOTU's current downloads before any update.
The user deferred Linux CueMix installation. No proprietary mixer application
or firmware updater was installed or run during commissioning.

The matching host policy also gives headphones priority and reduces the
priority of unused capture paths, especially loopback. Full multichannel
recording remains available through the device's Direct or Pro Audio profile;
the ordinary desktop profile is appropriate for stereo applications and games.
Changing to those recording profiles may require selecting the desktop profile
again afterward. qPWgraph 1.0.4 is installed for inspecting connections on demand.

Nix formatting, parsing and patch whitespace checks passed. The first full
desktop build failed because an unrelated, locally excluded package recipe was
absent from the Git-filtered package input. A private source snapshot retained
the tracked package files and that existing recipe without changing repository
exclusions. The next build passed evaluation and built dependencies, but the
kernel terminated two build workloads during global memory exhaustion. Reducing
build concurrency alone was insufficient. Separating evaluation from compilation
reduced the waiting build client's resident memory from roughly 2.5 GiB to
49 MiB while retaining the desktop resource protections and workstation queue.
An unrelated icon dependency also had a source hash mismatch. Its archive files
were verified against the pinned Git revision before using the corrected hash
in a private build input. The package checkout's hash was subsequently corrected
independently; its existing work was preserved.

The full desktop build and generation activation completed successfully. The
kernel and existing package versions remained unchanged. Temporary network and
WirePlumber configuration copies were removed. The generated policy gives the
headphone sink priority 1500 and loopback priority 100. A logical USB driver
rebind recovered the stock audio and MIDI functions, stereo headphone default,
webcam microphone default and requested unity software volume. The control link
used the generated `.link` and `.network` files, with both forwarding settings
disabled and no default route. USB-scoped discovery and a read-only WebSocket
control connection also succeeded after the rebind.

A silent playback probe negotiated 22 hardware playback channels in `S24_3LE`
at 48 kHz. Subsequent live profiling showed a 512-frame graph and zero errors
on the active MOTU driver; its data thread retained realtime priority 20.
These checks do not establish round-trip latency, sustained load tolerance,
physical unplug/replug, suspend recovery, cold boot or external input/output
performance. Normal repository rebuilds still need the existing locally excluded
package recipe supplied deliberately; the activated system does not depend on
the temporary build-input directory at runtime.
