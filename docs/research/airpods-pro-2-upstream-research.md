# AirPods Pro 2 stem controls on Linux

Research date: 2026-09-06. This note covers upstream behavior. Desktop runtime
observations and the final recommendation belong to the accompanying desktop
investigation. The user clarified during research that double pinch, triple
pinch, and long hold already work. Only single pinch needs repair.

## Recommendation

Keep the existing BlueZ and WirePlumber path. The desktop initially lacked a
Pause binding. Adding an unconditional pause action fixed pausing but the user
reported that a second pinch could not resume. The revised implementation maps
both Play and Pause to Noctalia's playback toggle. See the
[desktop investigation and corrected verification](airpods-pro-2-controls-research.md).
The original assumption that the second pinch would send Play was insufficient.
Installing an AirPods companion application is unnecessary for this repair.

## What the earbuds are supposed to do

Apple specifies one stem press for play/pause, two for next, three for previous,
and press-and-hold for listening modes on AirPods Pro 2. The requested gesture
set is the standard behavior. [Apple's playback controls](https://support.apple.com/en-us/102628).

Apple also says the default hold action switches between ANC and Transparency.
On an iPhone or iPad, Settings > AirPods > Press and Hold AirPods allows
Listening Mode or Siri per earbud and selection of the modes in the cycle.
Choose only Transparency and Noise Cancellation when configuring that cycle.
This is useful if the preference later changes, but the user reports that hold
already works. [Apple's press-and-hold settings](https://support.apple.com/en-us/108764).

Apple's cited page does not explicitly promise cross-platform persistence of
every setting. Do not claim that configuring an Apple device proves Linux
behavior. A reconnect and physical hold test establish that for this device.

## Linux translates commands into separate media keys

BlueZ 5.87's AVCTP mapping assigns these Linux input events:

| Bluetooth command | Linux input key |
| --- | --- |
| PLAY | `KEY_PLAYCD` |
| PAUSE | `KEY_PAUSECD` |
| FORWARD | `KEY_NEXTSONG` |
| BACKWARD | `KEY_PREVIOUSSONG` |

BlueZ first offers the command to a registered player handler. If that handler
does not handle it, the AVCTP path injects the mapped input event through its
uinput device. The code creates that device with a suffix consisting of a space followed by `(AVRCP)`.
[BlueZ 5.87 AVCTP implementation](https://github.com/bluez/bluez/blob/5.87/profiles/audio/avctp.c#L232-L410).

The AVRCP player handlers independently dispatch Play, Pause, Next, and
Previous. These are already interpreted Bluetooth commands, so desktop code
should not count pinches or add gesture timers.
[BlueZ AVRCP handlers](https://github.com/bluez/bluez/blob/5.87/profiles/audio/avrcp.c#L1544-L1624).

A generic play/pause keyboard key and the distinct Play event can resolve to
the same XKB keysym. The desktop's final bindings preserve that generic toggle
and also toggle on Pause, handling consecutive Pause events without requiring
accurate feedback of the selected player's playback state to the earbuds.

## Why the existing dummy player is enough

PipeWire 1.6.8 parses `bluez5.dummy-avrcp-player` as a Bluetooth monitor option,
defaults it to false, and registers its dummy player per adapter. The correct
WirePlumber location is `monitor.bluez.properties`. It is not a per-earbud
device rule. [PipeWire's option and registration code](https://github.com/PipeWire/pipewire/blob/1.6.8/spa/plugins/bluez5/bluez5-dbus.c).

The player only advertises `PlaybackStatus`; it does not expose playback
methods or control capability flags. This lets it report audio activity
without taking over the desktop's media-control implementation.
[PipeWire dummy player](https://github.com/PipeWire/pipewire/blob/1.6.8/spa/plugins/bluez5/player.c#L15-L66).
BlueZ's local-player Play/Pause methods decline control when the corresponding
capability flags are absent, allowing the input fallback above.
[BlueZ local-player capability checks](https://github.com/bluez/bluez/blob/5.87/profiles/audio/media.c#L2258-L2285).

The PipeWire property reference documents the dummy player as a workaround for
devices with broken playback or volume controls. Its rendered spelling and
example contain a typo, so use the hyphenated identifier in source.
[PipeWire property reference](https://docs.pipewire.org/page_man_pipewire-props_7.html).

LibrePods' Linux README recommends this option and warns against running
`mpris-proxy` alongside WirePlumber. That warning is guidance from LibrePods,
not evidence that every possible PipeWire/MPRIS-proxy configuration fails.
The existing dummy-player plus desktop-media-binding arrangement requires no
second control bridge. [LibrePods media-control troubleshooting](https://github.com/librepods-org/librepods/blob/53679cc90222e94ade84e66542d97ace2540e626/linux/README.md#media-controls-playpauseskip-not-working).

## Companion software and tradeoffs

The LibrePods main revision inspected was
`53679cc90222e94ade84e66542d97ace2540e626`. Its feature table distinguishes
switching the current listening mode, implemented on Linux, from configuring
the press-and-hold cycle, still marked unimplemented there. It also distinguishes
advanced features requiring Apple VendorID spoofing. Neither current-mode
switching nor a background companion is needed when the physical hold already
works. [LibrePods feature table](https://github.com/librepods-org/librepods/blob/53679cc90222e94ade84e66542d97ace2540e626/README.md#feature-availability).

The older Qt client's profile preference omits AAC, favors SBC-XQ/SBC, and can
restart WirePlumber when its expected profiles are missing. That conflicts with
this repository's prior AAC work. [Qt media controller](https://github.com/librepods-org/librepods/blob/53679cc90222e94ade84e66542d97ace2540e626/linux/media/mediacontroller.cpp#L152-L215).
The Rust rewrite at `672e65ad36eebf21ff1c1a508066f9197ee56d17` still has the
same preferred-profile list and a WirePlumber restart method.
[Rust media controller](https://github.com/librepods-org/librepods/blob/672e65ad36eebf21ff1c1a508066f9197ee56d17/linux-rust/src/media_controller.rs#L560-L612).

My security and performance recommendation is to reuse the already-running
input and desktop media services. A binding correction needs no additional
privileged daemon, input-device permissions, Bluetooth discoverability,
pairing-policy change, polling loop, or Apple identity spoofing. It also keeps
the existing media UI's active-player selection. These are consequences of
the proposed architecture, not measured resource benchmarks or a security
audit of companion projects.

## Verification

1. Capture one pinch while playing and one while paused from the AirPods AVRCP
   input device. Confirm the event codes and resulting XKB keysyms.
2. Confirm a pinch pauses and the next pinch resumes the same player.
3. Confirm ordinary keyboard play/pause still toggles normally.
4. Confirm double pinch, triple pinch, and hold keep their working behavior.
5. Reconnect the earbuds and repeat the play/pause check. Confirm playback
   retains its AAC profile.

No configuration or runtime changes were made for this upstream research.
