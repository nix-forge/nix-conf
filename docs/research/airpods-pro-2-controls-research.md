# AirPods Pro 2 single-pinch controls on desktop

Researched and applied on 2026-09-06. The verification results below distinguish
the tested desktop event path from physical stem gestures.

The user confirmed that double pinch, triple pinch, and the noise-control hold
already work. Only single pinch needs repair. The best first change is to
complete the desktop's existing media-key bindings. A separate AirPods client
is unnecessary for these requirements.

## What the desktop shows

Read-only checks on `desktop` established the following:

- BlueZ 5.87 has the AirPods paired, bonded, trusted, and connected.
- `/proc/bus/input/devices` and `hyprctl devices -j` both expose
  `AirPods Pro (AVRCP)` as an input device.
- PipeWire 1.6.8 is using A2DP AAC. WirePlumber 0.5.15 is active.
- `hosts/nixos/desktop/local/audio.nix` enables
  `monitor.bluez.properties."bluez5.dummy-avrcp-player"` and explicitly disables
  LibrePods. `mpris-proxy.service` is inactive.
- `hyprctl binds -j` confirms bindings for `XF86AudioPlay`, `XF86AudioNext`, and
  `XF86AudioPrev`. There is no `XF86AudioPause` binding.
- `modules/home/desktop/noctalia.nix` maps Play to `noctalia msg media toggle`,
  Next to `media next`, and Previous to `media previous`.
- Spotify is the sole MPRIS player in the sampled session and reports both
  `CanPlay=true` and `CanPause=true`. Noctalia exposes explicit Play, Pause,
  and PlayPause methods in its running D-Bus interface.

These initial observations establish a missing binding. They do not establish
which event this pair sends on a physical pinch. The initial research used only
read-only checks. Subsequent desktop-path verification and the applied fix are
recorded below; no physical gesture trace has been captured.

## Why the missing binding matters

BlueZ maps AVRCP PLAY to Linux `KEY_PLAYCD` and PAUSE to `KEY_PAUSECD`. It maps
FORWARD and BACKWARD to next and previous song keys. Play and Pause are
therefore distinct events in this path.
[BlueZ 5.87 mapping](https://github.com/bluez/bluez/blob/5.87/profiles/audio/avctp.c#L266-L270)

The installed XKB `symbols/inet` maps `KEY_PLAYCD` to `XF86AudioPlay` and
`KEY_PAUSECD` to `XF86AudioPause`. Its generic `KEY_PLAYPAUSE` also maps to
`XF86AudioPlay` at the ordinary modifier level. Consequently, a desktop binding
for Play does not cover the separate Pause event, and changing every Play
binding to an unconditional play action could break keyboard toggle buttons.
This mapping was inspected in the local Nix store's xkeyboard-config 2.41.

Noctalia already implements `media play`, `media pause`, and `media toggle`
through its selected MPRIS player. A new media-control service would duplicate
existing functionality.
[Pinned Noctalia implementation](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/dbus/mpris/mpris_service.cpp#L693-L710)

## Binding fix

The final binding in `modules/home/desktop/noctalia.nix` is:

```nix
(hyprBind "XF86AudioPause" "${noctalia} msg media toggle")
```

The existing `XF86AudioPlay` binding also uses `media toggle`. Both events now
act on Noctalia's selected player as a play/pause gesture. The generic keyboard
play/pause key retains its toggle behavior.

The first implementation used `media pause`. The user confirmed that it paused
successfully but could not resume. That invalidated the initial assumption
that a second pinch would necessarily arrive as a separate Play event. The
corrected desktop test repeats Pause events and expects playback to alternate.
It failed before the correction and passed afterward.

A plausible reason is playback-state feedback. PipeWire's dummy AVRCP player
reports aggregate Bluetooth audio activity using a playing counter, rather
than the selected MPRIS player's paused state. Another active stream may
therefore leave the Bluetooth player reporting Playing while Spotify is paused.
An earbud acting on that state may continue to request Pause. This explains how
the mismatch can occur, but no raw stem trace or simultaneous AVRCP status
capture was obtained for this pair, so that cause is not proven.
[PipeWire state reporting](https://github.com/PipeWire/pipewire/blob/1.6.8/spa/plugins/bluez5/player.c#L228-L240)
[PipeWire playing counter](https://github.com/PipeWire/pipewire/blob/1.6.8/spa/plugins/bluez5/player.c#L300-L322)

Using a toggle for either event avoids depending on that feedback for the
requested stem gesture. Noctalia's PlayPause method toggles the selected
player's actual playback state. This deliberately also makes a dedicated
`XF86AudioPause` keyboard button toggle on this desktop.
[MPRIS player specification](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html)

## Security, performance, and interface

The proposed binding executes an existing command as the logged-in user. It
adds no service, network listener, polling loop, raw Bluetooth access, or
permanent input-device permissions. Existing pairing restrictions remain
appropriate. Do not grant membership in the `input` group just to diagnose a
headset button.

The change does not touch the audio graph, codec, microphone profile, or buffer
settings. Keep the current AAC playback policy. Noctalia remains responsible
for player selection, so the stem controls and the visible media panel use the
same player. Keep the current lock-screen binding policy for this repair;
enabling controls while locked would be a separate behavior change.

Leave the working double pinch, triple pinch, and ANC/transparency hold alone.
Do not count pinches in a script or emulate a hold in the compositor. Keep
LibrePods disabled for this repair. The upstream research companion explains
its broader feature and integration tradeoffs.
[Upstream research](airpods-pro-2-upstream-research.md)

## Verification before declaring it fixed

1. Capture only the AirPods AVRCP input device during a single pinch while
   Spotify is playing and again while it is paused. Rediscover its event path
   after reconnecting; the sampled `/dev/input/event26` is not a stable name.
   Use a short, read-only event capture with no exclusive input grab. If elevated
   access is needed, confine it to this temporary diagnostic.
2. Match each event to the live Hyprland binding and observe Spotify's MPRIS
   PlaybackStatus. The pass condition is one pinch changing Playing to Paused
   and the next changing Paused to Playing, with one action per gesture.
3. Repeat after a Bluetooth reconnect and after changing playback state through
   Spotify's UI. Confirm the keyboard play/pause key still toggles.
4. Recheck double pinch, triple pinch, and long hold. Confirm AAC remains selected
   and Noctalia's media panel agrees with the player state. With multiple players
   open, verify the selected player receives the command.

No full system build was needed for research. Any later full desktop build must
run on host `desktop`, as required by the repository instructions.

## Applied fix and desktop-path verification

A temporary Python standard-library harness created a uinput keyboard using
the user's existing access. It sent the Linux media keys from BlueZ's AVRCP
fallback through running Hyprland bindings and Noctalia to Spotify. It read
Spotify's actual MPRIS status, destroyed the temporary device, and restored the
original playback state on both success and failure.

The original missing binding failed with `Expected Paused, got Playing`.
The first fix passed a Pause-then-Play sequence, but the user's physical test
showed pause without resume. That first test was too narrow.

The revised `python3 /tmp/airpods-controls-check/check.py` test sends consecutive
Pause events and expects Playing → Paused → Playing. Against the first fix it
failed with `AssertionError: Expected Playing, got Paused`. Against the final
toggle binding it passed:

```text
PASS: key 201 toggles both ways on consecutive presses
PASS: key 200 toggles both ways on consecutive presses
PASS: key 164 toggles both ways on consecutive presses
PASS: Pause key resumes after an external pause
```

Each key was exercised four times, alternating expected playback state.
The last check paused Spotify directly through MPRIS before injecting Pause,
which verified recovery after changing state through another control path.
This tests the desktop event path, not the radio or the physical stem.
After the revised binding went live, the user confirmed that a physical single
pinch resumes and the next pauses: "Both directions work now".
The temporary harness was removed after verification.

The Nix-generated `hypr/hyprland.lua` source built successfully on `desktop`.
An automated comparison confirmed the only change to the active generated file
was the Pause command changing from `media pause` to `media toggle`. The active
configuration symlink now points to that generated store file, protected from
garbage collection by `~/.local/state/nix/gcroots/airpods-hyprland`. The source
change is also in the repository for subsequent Home Manager activations.
A full system activation was unnecessary.

`hyprctl reload config-only` succeeded with no configuration errors. The binding
continues to run only on press, without repeat or lock-screen activation.
