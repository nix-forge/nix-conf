# AirPods Pro 2 on the NixOS desktop

Research date: 2026-09-04

## Live result

The desktop had two separate faults. BlueZ first established only the base
BR/EDR link, so WirePlumber had no audio card to expose in the sound panel.
Connecting the `a2dp-sink` profile immediately created the card and negotiated
AAC. The scoped `bluez5.auto-connect` rule now handles that partial-connection
case.

The original BlueZ entry also reported `Paired: yes` but `Bonded: no`. The
desktop deliberately disables unsolicited pairing after boot. Pairing while
the adapter remained non-pairable produced a temporary link key with
`store_hint 0`, which BlueZ discarded at disconnect. Temporarily setting the
adapter pairable while the case flashed white produced `store_hint 1` and a
stored bond. Pairing was disabled again afterward.

The deployed result passed three checks after an ordinary disconnect and
reconnect. BlueZ reported paired, bonded, trusted, connected, and services
resolved. PipeWire exposed the AirPods sink automatically with codec `aac`
and profile `a2dp-sink`. The sink is the default, unmuted output at 40 percent,
and automatic switching to the lower-quality headset profile is disabled.

## Recommendation

Fix the missing audio device in BlueZ, PipeWire, and WirePlumber. LibrePods is
not an audio driver and should not be used as the repair. Once the AirPods
appear as a PipeWire device, use the `a2dp-sink-aac` profile for music, games,
and video. Use the desktop's separate microphone for calls if playback quality
matters.

Do not install or auto-start the current LibrePods Linux application yet. Its
companion features are useful, but both its released Qt client and in-progress
Rust rewrite prefer SBC-XQ and SBC profiles without considering
`a2dp-sink-aac`. They also change the audio profile themselves. That behavior
works against the goal of keeping AirPods Pro 2 on AAC. A small upstream or
local patch could make LibrePods safe to add later.

The durable audio configuration should:

1. Keep PipeWire, pipewire-pulse, WirePlumber, and BlueZ enabled.
2. Keep WirePlumber's quality profile preference.
3. Leave the full upstream codec set enabled. Do not replace it with a global
   codec allowlist.
4. Add an AirPods-specific `bluez5.auto-connect = [ a2dp_sink hfp_hf ]` rule
   only if the live failure is a partial profile connection.
5. Select and persist `a2dp-sink-aac`, set the AirPods sink as the default, and
   unmute it after the first successful connection.
6. Keep headset auto-switching only if the AirPods microphone is wanted. For
   consistently high-quality playback, use a separate microphone and disable
   automatic HFP switching.

## What the current system already has

Evaluation of `nixosConfigurations.desktop` reports this stack:

| Component | Version or setting |
| --- | --- |
| PipeWire | 1.6.8 |
| WirePlumber | 0.5.15 |
| BlueZ | 5.87 |
| PipeWire audio and PulseAudio compatibility | Enabled |
| WirePlumber | Enabled as a per-user service |
| PulseAudio daemon | Disabled |
| Bluetooth controller mode | Dual, BR/EDR plus LE |
| WirePlumber profile preference | `quality` |
| Automatic headset switching | Enabled |

The NixOS PipeWire 1.6.8 build includes BlueZ support, SBC, FDK-AAC,
libfreeaptx, LC3, and LDAC. AAC is therefore compiled in already. The pinned
[nixpkgs PipeWire package lists those Bluetooth codec
dependencies](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/pi/pipewire/package.nix#L47-L55)
and [enables the BlueZ codec
backends](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/pi/pipewire/package.nix#L192-L246).

The repository also sets
`device.routes.mute-on-bluetooth-playback-removed = true`. WirePlumber says
this policy mutes devices when Bluetooth playback disappears and does not
automatically undo that mute. This is a sensible privacy guard, but the repair
must explicitly unmute the selected AirPods sink after reconnecting. See the
[WirePlumber setting definition](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/settings.html).

## The correct quality profile

Apple says AirPods wireless playback uses the Apple AAC Bluetooth codec and
also says Bluetooth playback is not lossless. Linux cannot turn this link into
lossless audio by increasing PipeWire's sample format or graph rate. The useful
quality choice is AAC over A2DP, not a high-rate PCM graph feeding a lower
quality headset profile. [Apple documents AAC and the Bluetooth lossless
limit](https://support.apple.com/guide/iphone/play-lossless-audio-iph14e213417/ios).

WirePlumber exposes supported A2DP codecs as separate profiles. Its BlueZ
monitor supports AAC, SBC, SBC-XQ, LDAC, aptX variants, LC3, and other codecs,
and enables all codecs available in the PipeWire build by default. The current
configuration's `bluetooth.profile-preference = "quality"` is already the
correct policy. [WirePlumber documents codec defaults and BlueZ
roles](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/bluetooth.html#monitor-properties),
and [documents the quality preference](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/settings.html).

PipeWire 1.6.8 already defaults its AAC encoder to FDK-AAC VBR quality mode 5
when no `bluez5.a2dp.aac.bitratemode` override exists. It caps the negotiated
AAC bitrate at 320 kbit/s and also limits it to what fits the Bluetooth MTU.
Adding `bluez5.a2dp.aac.bitratemode = 5` would only restate the running
version's default. [The PipeWire 1.6.8 AAC implementation contains the default
and bounds](https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/1.6.8/spa/plugins/bluez5/a2dp-codec-aac.c).

The target playback state is:

```text
device profile: a2dp-sink-aac
sink state: unmuted
default audio sink: the AirPods output
microphone: a separate desktop or USB input
```

## Microphone tradeoff

A2DP is the high-quality one-way playback profile. Using the AirPods
microphone requires HFP or HSP on the ordinary Linux Bluetooth path. When a
recording application opens that microphone, WirePlumber switches the device
to headset mode. WirePlumber describes the result plainly: headset mode has
considerably lower playback quality than A2DP. It switches back after capture
ends when automatic headset switching works normally. [The policy and quality
tradeoff are documented in the WirePlumber settings
reference](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/settings.html).

The best practical modes are:

| Use | AirPods profile | Microphone |
| --- | --- | --- |
| Music, games, and video | A2DP AAC | Separate desktop or USB input |
| Calls using only the AirPods | HFP/HSP, preferably mSBC if negotiated | AirPods |
| Always-high-quality playback during calls | A2DP AAC | Separate desktop or USB input |

Do not force mSBC globally. PipeWire enables it through its hardware quirks
database because it does not work on every headset. LibrePods cannot remove
this tradeoff. Its own feature table marks high-quality two-way audio as not
implemented. [LibrePods lists that limitation](https://github.com/librepods-org/librepods#feature-availability).

## Repair sequence for a connected device with no sound node

BlueZ connection state alone is not proof of an audio connection. WirePlumber
loads PipeWire's BlueZ monitor, watches the system BlueZ service, and creates
the audio device and nodes. It only creates them for the active logind session
by default. [WirePlumber documents this ownership
path](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/bluetooth.html#logind-integration).

Use this decision order on the live desktop:

1. Confirm `bluetoothctl info <MAC>` reports `Connected: yes`,
   `ServicesResolved: yes`, and the Audio Sink UUID.
2. Confirm `pipewire`, `pipewire-pulse`, and `wireplumber` are active in the
   logged-in user's systemd session.
3. Run `wpctl status --name`. If the AirPods are absent, inspect the
   WirePlumber user journal and the system Bluetooth journal before changing
   codecs.
4. Check that the Hyprland/UWSM logind session is active. Disabling seat
   monitoring hides the symptom but weakens correct multi-session ownership,
   so do not make that a default workaround.
5. If BlueZ connected only part of the device, make the computer initiate the
   audio profile with `bluetoothctl disconnect <MAC>` followed by
   `bluetoothctl connect <MAC> a2dp-sink`. BlueZ documents the optional profile
   argument and its `ConnectProfile` behavior in the
   [bluetoothctl manual](https://github.com/bluez/bluez/blob/master/doc/bluetoothctl.rst#connect).
6. Once WirePlumber exposes the card, select `a2dp-sink-aac`, set its sink as
   the default, and unmute it. WirePlumber's persistent profile storage and
   normal device profile restoration should retain that selection.

An AirPods Pro 2 report in the BlueZ tracker describes a closely matching
reconnect failure. A device-initiated connection appeared connected but did
not pass audio, while disconnecting and reconnecting from the computer worked.
The old PipeWire defect cited there was fixed before this system's version, so
the live transport paths and logs still need to match before treating it as
the cause. [The report includes both working and failing endpoint
layouts](https://github.com/bluez/bluez/issues/1175).

There is also a new open BlueZ report with the exact BlueZ 5.87, PipeWire
1.6.8, and WirePlumber 0.5.15 versions used here. Its failure is
`a2dp-sink profile connect failed: Protocol not available`. No maintainer fix
or diagnosis has been posted as of the research date. This is a log signature
to check, not enough evidence by itself to downgrade the stack.
[BlueZ issue 2435 records the version match and error](https://github.com/bluez/bluez/issues/2435).

If the reconnect works but the problem later returns, add this rule with the
actual AirPods card name:

```nix
services.pipewire.wireplumber.extraConfig."20-airpods-pro-2" = {
  "monitor.bluez.rules" = [
    {
      matches = [
        { "device.name" = "bluez_card.AA_BB_CC_DD_EE_FF"; }
      ];
      actions.update-props."bluez5.auto-connect" = [
        "a2dp_sink"
        "hfp_hf"
      ];
    }
  ];
};
```

WirePlumber documents `bluez5.auto-connect` as the control for connecting
profiles at startup or when only part of a device is connected. Keep it scoped
to the AirPods so it does not change connection behavior for every Bluetooth
device. [The property reference includes its accepted
profiles](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/bluetooth.html#device-properties).

## LibrePods assessment

LibrePods is companion software for Apple's proprietary AirPods control
protocol. On Linux it can expose noise-control modes, conversational awareness,
battery state, and ear-detection behavior. Those are separate from A2DP audio
transport. The project says spatial rendering is outside its scope and
high-quality two-way audio is not implemented. [The official feature table
separates implemented and missing features](https://github.com/librepods-org/librepods#feature-availability).

The Linux packaging is unsettled:

- The latest tagged Linux binary is `linux-v0.1.0`, published as a pre-release
  on 10 November 2025.
- The current Linux README says a Rust rewrite is in progress and recommends
  nightly workflow artifacts for testers.
- The pinned nixpkgs revision has a source-built `librepods` 0.2.5 package,
  but it builds the older Qt `linux` directory rather than the Rust rewrite.

These facts are visible in the official [Linux README](https://github.com/librepods-org/librepods/blob/main/linux/README.md),
[release list](https://github.com/librepods-org/librepods/releases/tag/linux-v0.1.0),
and [pinned nixpkgs package](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/li/librepods/package.nix).

More importantly, the Qt client considers only `a2dp-sink-sbc_xq`,
`a2dp-sink-sbc`, and the generic `a2dp-sink` profile. It prefers them in that
order and never names `a2dp-sink-aac`. When it cannot find one of those
profiles, it restarts WirePlumber itself. It can also set the card profile to
`off` when both buds are removed. [The behavior is in LibrePods'
`MediaController`](https://github.com/librepods-org/librepods/blob/main/linux/media/mediacontroller.cpp#L152-L215).
The Rust rewrite fixes the broad availability check, but its preferred list
still starts with SBC-XQ and omits AAC. It also defaults
`disconnect_when_not_wearing` to true. [The current rewrite source shows the
profile list](https://github.com/librepods-org/librepods/blob/linux/rust/linux-rust/src/media_controller.rs#L525-L572)
and [the default disconnect behavior](https://github.com/librepods-org/librepods/blob/linux/rust/linux-rust/src/media_controller.rs#L58-L75).

That is why LibrePods should stay out of the first repair. If it is added later,
patch it to prefer `a2dp-sink-aac`, disable profile-off behavior by default,
and remove the automatic WirePlumber restart. Its documented
`bluez5.dummy-avrcp-player = true` setting can then be added for stem media
controls. Do not run `mpris-proxy` at the same time, which the LibrePods Linux
README says conflicts with WirePlumber. [The upstream instructions cover the
AVRCP setting and conflict](https://github.com/librepods-org/librepods/blob/main/linux/README.md#media-controls-playpauseskip-not-working).

## Verification after deployment

1. `wpctl status --name` shows an AirPods device and stereo output.
2. The active card profile is `a2dp-sink-aac` during ordinary playback.
3. The AirPods sink is the default and is not muted.
4. Audio plays after putting both buds in the case, waiting for disconnect,
   and taking them out again.
5. Opening the selected desktop microphone does not change the AirPods profile.
6. If the AirPods microphone is tested, the profile switches to HFP/HSP only
   while capture is active and returns to A2DP AAC afterward.
7. The system journal contains no A2DP `Protocol not available`, transport
   acquire, or repeated profile-connection failures.

The final codec and microphone checks require the connected AirPods. A Nix
evaluation can prove that AAC support exists, but it cannot prove which codec
the earbuds negotiated.
