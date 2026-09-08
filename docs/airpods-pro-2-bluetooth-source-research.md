# AirPods Pro 2 Bluetooth reliability on the desktop

Research date: 2026-09-07. Primary-source research for the desktop investigation.
No configuration or runtime settings were changed for this research.

The strongest first step is to improve the desktop's external antenna
position. The user confirmed both antennas are connected behind the PC.
Movement-dependent dropouts fit weak reception or interference, but
that is a working hypothesis, not a diagnosis. The comparison with the MacBook
does not isolate the cause unless both computers stay in the same location
while the listener follows the same route.

## What the running desktop showed

These are read-only observations from the desktop on September 7, 2026.
They describe the running system, rather than relying only on Nix settings or
the earlier audio research notes.

| Item | Observed state |
| --- | --- |
| Motherboard | MSI MAG B650 TOMAHAWK WIFI, MS-7D75 |
| Radio | MediaTek MT7922, PCI `14c3:0616`, Bluetooth USB `0e8d:0616` |
| Software | Linux 7.2.0, BlueZ 5.87, PipeWire 1.6.8, WirePlumber 0.5.15 |
| Bluetooth firmware build timestamp | `20260724143815` in the kernel journal |
| Antennas | Both connected behind the PC, confirmed by the user |
| Wi-Fi | 5805 MHz, channel 161, therefore already on 5 GHz |
| Playback | Spotify routed to AirPods, A2DP with AAC, configured AAC mode 5 |
| Pairing | AirPods paired, bonded and trusted; adapter not pairable or discoverable |
| Audio policy | Automatic headset switching disabled; AVRCP player enabled |
| USB runtime power | Bluetooth device active; autosuspend allowed after 2000 ms idle |
| Audio scheduling | PipeWire, PipeWire Pulse and WirePlumber data loops currently `TS`, no realtime priority |

The configured graph defaults to 512 frames at 48 kHz with a 256 to 2048 frame
range. During `pw-top -b -n 5`, the active driver selected 2048 frames. The
AirPods sink error counter stayed at zero and Spotify's counter stayed at 380.
The latter is a historical count, not 380 failures during this observation.
This short sample did not reproduce a walking-related dropout or establish
that playback remains reliable elsewhere in the house.

The current configuration is in
[desktop audio](../hosts/nixos/desktop/local/audio.nix),
[desktop platform](../hosts/nixos/desktop/local/hardware/platform.nix), and
[shared Bluetooth policy](../modules/nixos/hardware/bluetooth.nix).

## A separate audio scheduling problem

The system journal records successful realtime priority 20 grants for the audio
data loops on September 5. On September 6 at 16:55:33 PDT, RTKit reported that
its canary thread was starving and explicitly demoted those same PipeWire,
PipeWire Pulse and WirePlumber threads. The live thread listing confirms they
remain at normal priority. This is a demonstrated loss of the intended audio
scheduling, but its contribution to the distance-dependent symptom remains
unmeasured.

RTKit deliberately demotes threads when its watchdog detects starvation. It
provides bounded realtime scheduling through a privilege broker, and PipeWire
supports that path. Keep this protection. Disabling the watchdog, handing out
unrestricted realtime privileges or repeatedly overriding a demotion would
conflict with the user's performance and security constraints.
[RTKit design](https://github.com/heftig/rtkit/blob/master/README),
[PipeWire realtime module](https://docs.pipewire.org/page_module_rt.html).

The practical follow-up is to restore the normal audio services through RTKit
at a planned playback pause, verify that the data loops regain `RR/20`, and
repeat the same route. An ordinary restart of the user audio services is a
recovery test, not a demonstrated permanent fix. If demotion recurs, investigate
the starvation event before changing scheduling policy. This research did not
restart services or interrupt playback.

Useful read-only checks are:

```bash
ps -eLo pid,tid,cls,rtprio,ni,comm | rg 'pipewire|data-loop|wireplumber'
journalctl -b -u rtkit-daemon --no-pager -g 'canary|demot|priority'
pw-top -b -n 30
journalctl --user -b -u pipewire -u pipewire-pulse -u wireplumber --no-pager -p warning -n 60
```

## What the Bluetooth warnings do and do not establish

The repeated kernel warning about unknown connection handle 3837 has a specific
upstream explanation. A MediaTek-authored patch dated August 26, 2026 identifies
that reserved handle as a firmware debug event which the driver sends to the
ordinary receive path. The proposed fix routes it to diagnostics. This supports
treating the warning as a logging-path issue rather than proof of lost music
packets. It does not establish that every controller warning is harmless or
that the patch improves range. No patch was applied.
[MediaTek patch submission](https://lkml.iu.edu/2608.3/05248.html).

There are more relevant transport symptoms. At 15:33:49 PDT on September 7,
WirePlumber recorded an unexpected AirPods transport termination after buffer
warnings. At 17:04:07 it logged missing packet completion reports. PipeWire's
source emits the latter warning when pending send or completion timestamps
remain unresolved for more than a second. The wording suggests a firmware
problem but is not a device-specific diagnosis. A timestamped walking test must
distinguish radio loss, controller behavior and host scheduling stalls.
[PipeWire 1.6.8 completion tracking](https://github.com/PipeWire/pipewire/blob/1.6.8/spa/plugins/bluez5/bt-latency.h).

## Antennas and interference

The desktop investigation identified an MSI MAG B650 TOMAHAWK WIFI motherboard
and MediaTek MT7922 controller. MSI labels the rear connectors as shared
Wi-Fi/Bluetooth antenna connectors. Its manual, printed page 25, instructs the
owner to fasten both antennas and orient them. Bluetooth needs those antennas
even if the desktop uses Ethernet. The final sentence is an inference from
MSI's shared-antenna design, not a measurement of this installation.
[MSI specifications](https://www.msi.com/Motherboard/MAG-B650-TOMAHAWK-WIFI/Specification),
[MSI manual](https://download.msi.com/archive/mnu_exe/mb/MAGB650TOMAHAWKWIFI.pdf).

Bluetooth SIG identifies antenna location and design, receiver sensitivity,
transmit power, and obstacles as contributors to range. Walls and other
obstacles weaken the signal. An exposed position above the desk, away from the
metal case and cable bundle, is therefore worth testing. A compatible cabled
antenna base could make that placement practical if the stock antennas remain
behind the tower. Compatibility, cable loss, connector type, and improvement
would need checking before a purchase. Bigger gain numbers alone do not establish
better whole-house coverage.
[Bluetooth SIG on range](https://www.bluetooth.com/learn-about-bluetooth/key-attributes/range/).

Intel documents radio interference in the 2.4 GHz band from some USB 3 devices
and cables. That is a reason to separate the antenna from USB hubs, storage,
docks, and their cables. It does not establish that the desktop's USB devices
are causing this problem. Physical separation preserves their USB transfer
speed; globally disabling USB 3 would sacrifice performance without proving a
benefit.
[Intel USB 3 interference white paper](https://www.intel.com/content/www/us/en/content-details/841692/usb-3-0-radio-frequency-interference-impact-on-2-4-ghz-wireless-devices-white-paper.html).

Intel recommends 5 GHz Wi-Fi when possible to reduce interference with
Bluetooth. The desktop investigator observed Wi-Fi at 5805 MHz, so the desktop
already follows this advice. Nearby wireless devices may still contribute
interference. Changing bands is not an established fix for this installation.
[Intel Bluetooth FAQ](https://www.intel.com/content/www/us/en/support/articles/000005821/wireless/legacy-intel-wireless-products.html).

Apple's dropout guidance recommends checking stored audio near the source,
then considering distance, walls, busy Wi-Fi environments, poorly shielded
cables, and other interference. For this investigation, use one downloaded
track, the same volume and route, and stationary source computers. Repeat after
each antenna change. If a downloaded track also fails only farther away, that
supports a radio problem over an internet-streaming problem. Nearby failures
also warrant checking the driver and audio stack.
[Apple dropout troubleshooting](https://support.apple.com/en-ie/102214).

## Audio quality and Bluetooth capabilities

The desktop investigator observed active AAC A2DP playback and an AAC
`bitratemode` override of `5`. There is no evidence that missing AAC support is
the problem. PipeWire documents mode `0` as constant bitrate and modes `1`
through `5` as variable-bitrate quality levels. A lower setting may change both
quality and bandwidth demands, so it is a controlled diagnostic option, not an
improvement that can be promised without tradeoffs. Preserve the existing
setting while testing antenna placement first.
[PipeWire Bluetooth properties](https://docs.pipewire.org/page_man_pipewire-props_7.html).

PipeWire 1.6.8 already defaults this AAC option to mode 5, so removing the
explicit override would not improve this version's behavior. Increasing the
PCM graph sample rate does not create a better Bluetooth codec. There is no
verified codec change here that simultaneously improves fidelity and range
without a tradeoff.
[PipeWire 1.6.8 AAC implementation](https://github.com/PipeWire/pipewire/blob/1.6.8/spa/plugins/bluez5/a2dp-codec-aac.c).

WirePlumber enables available A2DP codecs by default. Listing additional codecs
cannot add decoder support to the earbuds. Its documentation also distinguishes
A2DP music playback from HFP/HSP headset operation.
[WirePlumber Bluetooth configuration](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/bluetooth.html).

WirePlumber normally switches to headset mode when an application records from
the Bluetooth microphone, then restores the previous profile. Its documentation
states that headset mode has substantially lower playback quality. Disabling
this behavior can impair microphone use, so that is unsuitable as an
unconditional fix under the user's UX requirement. It also does not explain a
failure that follows distance while the device stays in A2DP.
[WirePlumber headset switching](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/settings.html).

Apple lists Bluetooth 5.3 for both AirPods Pro 2 variants. That version number
does not establish a usable Linux LE Audio path. Bluetooth SIG distinguishes
the Classic radio used for conventional audio from the LE radio; LE Coded
range claims concern the latter. Buying a higher-numbered Bluetooth adapter or
forcing LE cannot be assumed to improve an existing AAC A2DP connection.
[AirPods Pro 2 specifications](https://support.apple.com/en-us/111851),
[USB-C model specifications](https://support.apple.com/en-gb/111834),
[Bluetooth SIG technology overview](https://www.bluetooth.com/learn-about-bluetooth/tech-overview/),
[Bluetooth SIG LE Coded description](https://www.bluetooth.com/learn-about-bluetooth/feature-enhancements/).

Apple documents AAC for conventional AirPods Bluetooth audio. The USB-C AirPods
Pro 2 model supports lossless audio through a proprietary wireless protocol when
paired with Apple Vision Pro. This does not document lossless playback from a
MacBook or a general Linux adapter. There is no primary-source evidence here
that the MacBook's better range comes from that proprietary lossless mode.
[Apple lossless audio guidance](https://support.apple.com/en-us/118295).

## Changes that fit the user's constraints

Correcting antenna attachment and improving placement are the best first
candidates because they retain the codec, controls, microphone policy, pairing,
and encryption settings. These are properties of the proposed changes, not a
measured security or performance audit. They cannot guarantee coverage through
every wall in the house.

Keep AirPods firmware current using the MacBook. Apple provides the update
procedure and version check in Bluetooth settings. The earbuds update in their
powered charging case near a paired Apple device connected to Wi-Fi. Apple has
also shipped Bluetooth authentication fixes for AirPods, supporting the choice
to update rather than downgrade firmware. An update is maintenance, not proof
of a fix for these dropouts.
[Apple firmware instructions](https://support.apple.com/en-us/106340),
[Apple firmware security update](https://support.apple.com/en-us/102783).

Do not globally disable USB autosuspend as a range tweak. Linux defines
autosuspend around device idleness and permits control for an individual USB
device. If logs and runtime power state show a suspend/resume defect, a narrowly
scoped workaround could be tested, but it has a power-use tradeoff. Continuous
playback failures that track distance need stronger evidence for this cause.
[Linux USB power management](https://docs.kernel.org/driver-api/usb/power-management.html).

The desktop already enables `FastConnectable`. BlueZ describes it as faster
connection establishment with increased power use, so it is not a new remedy
for an established music stream. Retain dual-mode Bluetooth, existing pairing
restrictions, privacy, Secure Connections and the current nonexperimental
configuration. This research found no range benefit that requires relaxing
those settings.
[BlueZ configuration reference](https://github.com/bluez/bluez/blob/5.87/src/main.conf).

An adapter replacement becomes reasonable if antenna placement fails to help
and controller-specific faults persist. Choose it using verified Linux support
for its exact chipset and hardware revision, plus antenna placement, rather
than a Bluetooth version or advertised outdoor distance. A replacement means
pairing again and testing controls, microphone use, reconnects, and suspend, so
it is not automatically a UX-neutral upgrade. No particular replacement is
recommended by this research.

## Recommended order and success criteria

1. Test a downloaded track along the usual route with the desktop stationary.
   Record where and when sound breaks up. Place the MacBook in a comparable
   position for its own test instead of carrying it along.
2. Move the desktop antennas into an exposed position, away from the case and
   USB 3 cables. If a cabled base is needed, verify connectors and use a short,
   low-loss cable rather than buying on gain claims alone. Repeat the route
   without changing the codec. Check Wi-Fi performance too because it shares
   the antennas.
3. At a playback pause, restore normal audio scheduling through RTKit and
   repeat the route. Check for recurring watchdog demotions and new audio
   errors. Do not combine this with the antenna change if the aim is to learn
   which helped.
4. If dropouts remain, capture a timestamped failure and investigate the
   transport warnings against the exact kernel and firmware versions. Only
   then evaluate a specific software update or replacement controller.

Success means repeated walks without audible gaps while AAC, stem controls,
normal reconnection, pairing restrictions and ordinary Wi-Fi performance are
preserved. No walking test was completed during this research. The measured
benefit of repositioning, the MacBook's comparison position and the cause of
RTKit starvation remain unknown. No Nix build was needed for this research-only
documentation change.
