# Wootility 80HE research

Reviewed: 2026-10-07. Scope: Wooting 80HE, Wootility 5.4.2,
Linux HID access, USBGuard, and onboard profile design. Root repository
research base `84e37f5d83e1b218ce8c2c843fe3f9ead479b12c`.

## Answer

Use Wootility 5.4.2, the current stable release. It was released on
9 September 2026 and adds initial 80HE+ support. Existing 80HE keyboards
remain supported. [Official 5.4.2 release notes](https://wooting.io/wootility/changelogs/5.4.2).

Linux configuration needs two independent permissions. USBGuard must authorize
the keyboard's USB identity, and the active desktop session must have read and
write access to its configuration HID interface. Firmware restore has a
different USB identity, so a normal-mode authorization does not prove restore
will work. Keep these permissions in Nix and keep keyboard profiles as reviewed
assets that Wootility writes to onboard memory.

## Installation decision

Install the maintained stable Wootility on both hosts, but do not start it at login and do not
enable Wooting Background Service by default. The keyboard stores its normal
profiles onboard, so Wootility can stay closed outside configuration and
firmware work. This avoids paying the memory and CPU cost of an Electron app
that is not doing anything useful.

The NixOS desktop should use the Wootility and udev support already in
nixpkgs. The earlier package investigation evaluated Wootility 5.4.1. The
nixpkgs `hardware.wooting.enable` option installs both `pkgs.wootility` and
`pkgs.wooting-udev-rules`. A second Linux package in nixpkgs-personal would
duplicate maintained upstream work. [The current nixpkgs module is only those
two assignments](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/nixos/modules/hardware/wooting.nix#L10-L13),
and [the current package is Wootility
5.4.1](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wootility/package.nix#L8-L18).

The Apple Silicon laptop does need a personal package because nixpkgs marks
its Wootility package Linux-only. Package Wooting's arm64 DMG without changing
the application bundle. Generic fixup, wrapping the executable inside the
bundle, or editing `Info.plist` would invalidate Wooting's signature. Put any
command-line symlink outside `Wootility.app`, keep `dontFixup = true`, and
install it through the existing shared Home Manager module.

For routine edits, `https://wootility.io` in an up-to-date Chromium browser is
the safer first choice if it detects the keyboard. Keep the installed desktop
app for offline use, firmware recovery, and cases where the browser cannot use
WebHID. Wooting calls the web edition fast, secure, and lightweight, but only
documents Chromium-family browsers. Firefox and Safari do not work. [Wooting's
download page describes the two editions](https://wooting.io/wootility), and
[its troubleshooting guide documents the permission prompt and supported
browsers](https://help.wooting.io/article/92-wootility-doesnt-detect-my-wooting-keyboard#wootility-web).
Helium is Chromium-based but is not one of Wooting's named supported browsers,
so the native app remains the dependable path on these hosts.

## Earlier release and artifact verification

The following checks concern 5.4.1 artifacts, reviewed on 4 September 2026.
They do not verify the hashes or bundle contents of 5.4.2.

Wootility 5.4.1 was the stable release on that date. Wooting
released it on 13 July 2026 as a fix for Background Service updating. The 5.4
series adds automatic profile linking, guided restore, and Advanced Key
presets. Its firmware notes also include an 80HE lock-up fix. [The 5.4.1
changelog lists the release, downloads, and
changes](https://wooting.io/wootility/changelogs/5.4.1).

The official update metadata publishes SHA-512 digests and sizes. The Nix
SHA-256 values below were independently calculated from the same first-party
files and agree with the current nixpkgs Linux package.

| Host | First-party artifact | Size | Nix SHA-256 |
| --- | --- | ---: | --- |
| NixOS x86_64 | [`Wootility-5.4.1.AppImage`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-linux/Wootility-5.4.1.AppImage) | 192,619,636 bytes | `sha256-QqkkfLi0teDH5E0mm4hnY42msgE/z1RV1Rl4+Tt+TaQ=` |
| macOS arm64 | [`Wootility-5.4.1-arm64.dmg`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-mac/Wootility-5.4.1-arm64.dmg) | 135,780,240 bytes | `sha256-9237eJ7PzSWkJ7mSnzwJV040YnC3V5nOtX5UtuxiW6w=` |

The controlling machine-readable files are Wooting's
[`latest-linux.yml`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-linux/latest-linux.yml)
and
[`latest-mac.yml`](https://wootility-updates.ams3.cdn.digitaloceanspaces.com/wootility-mac/latest-mac.yml).
Do not package the floating download redirect. Pin the versioned CDN URL and
hash so a compromised or changed response cannot silently alter a rebuild.

Wootility v5 supports the 80HE and every older Wooting keyboard. Version 5.0
also introduced the coherent navigation, profile manager, tooltips, quick
settings, and 80HE Light Indicator controls that make v5 the right UI rather
than the older v4 branch. [Wooting's v5.0 release notes describe the redesign
and 80HE support](https://wooting.io/wootility/changelogs/5.0.0).

## Linux device access

Do not run Wootility or a browser as root. Do not add the user to the `input`
group. Either action grants far more access than this keyboard needs.

Wooting's current Linux instructions cover legacy vendor `03eb` product IDs
and all devices under its newer vendor ID `31e3`. The Wooting 80HE is vendor
`31e3`, base product `1400`; its alternative gamepad modes use `1401` and
`1402`. [Wooting's maintained SDK defines those
IDs](https://github.com/WootingKb/wooting-rgb-sdk/blob/98364bcd85aa267ee1cd657197f5d886175251f1/src/wooting-usb.c#L34-L57).

The official example sets mode `0660`, group `input`, and `uaccess`. Nixpkgs
deliberately keeps only `TAG+="uaccess"` for both `hidraw` and `usb`. That is a
better policy here. systemd-logind grants an ACL to the active local session,
while users in a broad input-reading group do not receive permanent access.
[Wooting explains its full rule and permission
model](https://help.wooting.io/article/147-configuring-device-access-for-wootility-under-linux-udev-rules),
and [nixpkgs carries the reduced
rules](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wooting-udev-rules/wooting.rules#L1-L16).

Use `hardware.wooting.enable = true` rather than copying the rules into this
repository. This also keeps restore and alternate device modes working. A
rule narrowed only to product `1400` looks tidier but can fail when firmware
changes the product ID during update or restore.

The upstream AppImage's desktop entry requests `--no-sandbox`. The nixpkgs
wrapper removes that flag and supplies the Wayland and input-method flags when
`NIXOS_OZONE_WL` and `WAYLAND_DISPLAY` are set. Keep the nixpkgs wrapper rather
than placing the raw AppImage in `home.packages`. [The package's wrapper and
desktop-entry rewrite are visible
upstream](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wootility/package.nix#L20-L40).

## Earlier macOS provenance

The 5.4.1 Apple Silicon DMG was mounted read-only and checked before packaging:

- `Wootility.app` contains a thin arm64 executable and declares macOS 11.0 as
  its minimum version.
- `codesign --verify --deep --strict` succeeds.
- Gatekeeper accepts it as a notarized Developer ID application.
- The signer is `Developer ID Application: Wooting Technologies B.V.
  (35RZSMAL44)`, Team ID `35RZSMAL44`, and the notarization ticket is stapled.
- The hardened-runtime signature has only the JIT entitlement expected by an
  Electron application.

Those checks bind the package to Wooting's Apple identity in addition to the
fixed Nix hash. Preserve the bundle byte-for-byte with `cp -a`. No udev rule or
privileged helper is required for ordinary USB HID access on macOS.

The bundle contains generic camera, microphone, and Bluetooth usage strings,
and it permits arbitrary network loads in App Transport Security. A USB
Wooting 80HE does not need those three privacy permissions. Do not grant them
if macOS prompts unexpectedly.

## Earlier artifact inspection and privacy limits

Wootility is proprietary software. Wooting does not publish the application
source in its GitHub organization, and nixpkgs classifies the binary as
`lib.licenses.unfree`. Keep that metadata rather than assigning a license from
one of Wooting's separate open-source SDKs. [The nixpkgs package records the
unfree license and Linux-only support](https://github.com/NixOS/nixpkgs/blob/cfcd1628672a7e89d65cd6bc9b33bd2bfc223981/pkgs/by-name/wo/wootility/package.nix#L45-L56).

The native 5.4.1 artifact bundles Electron 37.6.1 and Chromium 138. Electron
37 reached end of support on 13 January 2026, six months before Wooting
released Wootility 5.4.1. This is the strongest reason to prefer Wootility Web
inside a current Chromium build for normal configuration. [Electron's release
schedule gives the end-of-life date](https://releases.electronjs.org/schedule),
and [Electron 37.6.1 identifies its Chromium and Node
versions](https://releases.electronjs.org/release/v37.6.1).

Static inspection of the pinned artifact found further desktop hardening gaps.
Its local `BrowserWindow` disables context isolation, enables `webviewTag`,
automatically approves HID access for Wooting vendor IDs, and permits local
network requests. It does disable Node integration, rejects non-listed device
vendors, and sends new windows to the external browser. Electron recommends a
current framework, context isolation, renderer sandboxing, explicit permission
handling, and strict navigation controls. [Electron's security checklist is
the relevant upstream baseline](https://www.electronjs.org/docs/latest/tutorial/security).
Nix packaging can preserve Chromium's process sandbox on Linux, but it cannot
repair renderer settings inside this closed application.

The same artifact initializes PostHog with autocapture, page-view, and
page-leave collection. It also initializes Sentry with normal session replay
off and a 10 percent replay sample when an error occurs. Wooting's policy says
it collects IP address, browser and device data, page interactions, and data
needed for software features, and may use personal information for product
development and marketing. It also says that Do Not Track does not change its
collection. [The current Wooting privacy policy states those
terms](https://wooting.io/policies/privacy-policy).

There is no Nix-side switch that can safely remove the telemetry without
rewriting the signed app or risking breakage of Wootility's API calls. The
practical containment is simple: do not log in unless account-backed features
are wanted, close Wootility after use, and leave the optional service off.

## Updates and Background Service

Wootility checks for application updates at launch but does not download or
install them automatically. An in-app replacement is the wrong update path
for a Nix-store application. Update the nixpkgs input for Linux and the pinned
nixpkgs-personal source for macOS, then rebuild. The fixed source hash is part
of the security boundary.

Wooting Background Service is separate from the editor. Version 5.4 uses it to
watch the foreground application and switch keyboard profiles. Earlier 80HE
features can show CPU use, volume, Discord mute state, and notifications on
the Light Indicator. Wooting says Wootility itself can close once the service
is running. [The current setup and runtime behavior are documented in the
5.4.1 notes](https://wooting.io/wootility/changelogs/5.4.1#automatic-profile-switching-with-app-linking),
and [the original 80HE service features are documented in
5.2.1](https://wooting.io/wootility/changelogs/5.2.1#80he-introducing-background-service).

Do not install or auto-start the service during Nix activation. It expands
the amount of desktop activity Wooting software can observe and consumes
resources continuously. If App Linking or a live Light Indicator is wanted
later, enable the service deliberately in Wootility, verify the installed
service and its startup entry, and keep Wootility closed. This is both faster
and narrower than leaving the full editor running.

## Verification

Evaluation and package checks can run anywhere. Per this repository's
`AGENTS.md`, run the full desktop closure build on `desktop`, normally through
`just desktop-build` from another host.

After deployment:

1. Confirm the configured package version matches the intended stable release.
2. On NixOS, confirm the installed rule contains `TAG+="uaccess"` and no
   `GROUP="input"`, then check the active session receives an ACL on the
   Wooting `hidraw` device.
3. Launch from the application menu without `sudo`. The device indicator
   should turn green and the 80HE should appear by name.
4. On macOS, run `codesign --verify --deep --strict` and `spctl --assess` on
   the installed `Wootility.app`; both should still pass.
5. Duplicate or export a profile before the first firmware change. Test a
   harmless setting, write it to the keyboard, restart Wootility, and confirm
   the onboard profile remains.
6. Use the stable Wootility and firmware channels. A firmware update should
   use a direct cable and stable USB power. Wootility includes the firmware
   available when it shipped, which gives it an offline recovery path if its
   firmware service cannot be reached. [Wooting documents the bundled
   fallback](https://help.wooting.io/article/146-error-during-update-or-restore#firmwaredata).

The last device-connect and profile-write checks require the physical 80HE.
They cannot be proven by a Nix build alone.

## USBGuard and update-mode diagnosis

USBGuard authorizes USB devices before applications can access their interfaces.
udev ACLs authorize a user after the device has been accepted. Therefore an
allowed, usable typing interface does not establish that the configuration
interface has a user ACL. Conversely, correct udev rules cannot unblock a USB
device that USBGuard rejects. [USBGuard describes its use of Linux USB device
authorization](https://usbguard.github.io/).

A USBGuard rule can match product ID, name, descriptor-derived hash, port, and
interface set. Rules that require all these attributes match only that identity.
Changing gamepad mode or entering a bootloader can change enough attributes that
the original rule stops matching. This is an inference from the
[documented match semantics](https://usbguard.github.io/documentation/rule-language)
and Wooting's separate operating and restore modes.

Keep normal-mode rules tied to the known keyboard. Add explicit, constrained
update-mode authorization after identifying that mode from Wootility's matching
release or a live enumeration. Do not solve an update problem by permitting
all USB devices or disabling USBGuard. Matching a vendor ID identifies a claimed
manufacturer; USB descriptors are not cryptographic authentication.

The official RGB SDK defines 80HE base ID `31e3:1400` and alternative product
suffixes `0`, `1`, and `2` for gamepad compatibility. These are operating-mode
IDs, not evidence for any bootloader ID. [First-party USB enumeration
source](https://github.com/WootingKb/wooting-rgb-sdk/blob/98364bcd85aa267ee1cd657197f5d886175251f1/src/wooting-usb.c).

The current official recovery article specifies holding Pause and Right Arrow
while reconnecting an 80HE. Look for the device named Wooting Restore. The
article describes dark main RGB and blue corner keys, then Wootility's Help and
Troubleshoot recovery flow. It does not publish a textual 80HE bootloader PID.
Back up profiles and identify the actual ISO or ANSI layout before restore.
[Official recovery guide](https://help.wooting.io/article/90-how-to-restore-reset-my-wooting-one-or-wooting-two-flaretech).

Read the exact update error before assuming USBGuard is the cause. Wooting
separates bootloader connection failures, firmware-data download failures, and
other communication errors. A direct cable, stable power, another port, and a
second computer help separate transport problems from permissions.
[Update error guide](https://help.wooting.io/article/146-error-during-update-or-restore).

## Profile storage and declarative limits

The 80HE supports four onboard profiles. The default shortcut selects them with
Fn plus 1, 2, 3, or 4. Keep a typing profile in the first slot and retain these
shortcuts in every profile. Wootility can close after saving the profiles.
[80HE quickstart](https://wooting.io/quickstart/keyboard/wooting-80he/prebuilt).
The first saved profile becomes the default after USB power loss. If power
remains, the previously active profile can remain selected.
[Startup-profile guide](https://help.wooting.io/article/104-how-to-change-default-profile-at-startup).

The official supported profile-sharing workflow is My Profiles, Import profile,
then paste a profile code. Wooting's Valorant guide publishes working examples,
including an 80HE TenZ profile, but that profile enables Rappy Snappy and should
not be reused unchanged for CS2. [Official import example and settings
reference](https://wooting.io/post/wooting-valorant-guide-in-game-benefits-settings-and-pro-profiles).

No stable public full-profile JSON schema, full configuration API, or supported
command-line profile writer was found in the official sources reviewed. The
[Analog SDK](https://github.com/WootingKb/wooting-analog-sdk/blob/develop/README.md)
reads analog key values for applications. The
[RGB SDK](https://github.com/WootingKb/wooting-rgb-sdk/blob/main/README.md)
controls lighting. Neither documents an editor for actuation, advanced keys,
onboard profile serialization, or firmware flashing.

A JSON file containing chosen settings is a specification until Wootility can
import it and save it successfully. Do not label it a native profile export
without checking that path. A share code depends on Wooting's service and is
not a self-contained local backup. UI automation or inspected application
internals can apply a profile, but must pin the app version, preserve unknown
fields, and verify the saved result. A Nix activation should never silently
overwrite onboard profiles or flash firmware.

Nix can own package versions, udev access, USBGuard policy, reviewed profile
assets, and a command that explicitly opens the editor or imports a compatible
asset. Onboard state still needs a verified save through the application's
supported path. Existing profiles should be exported or duplicated before any
replacement. The 5.4 recovery flow moves known profiles to inactive storage
rather than deleting them. Its App Linking requires Wooting Background Service;
the editor itself can close. Linux and Wayland behavior must be tested before
promising automatic foreground-app switching.
[5.4 behavior](https://wooting.io/wootility/changelogs/5.4.1).

## Work and game profile recommendations

The following values are starting points chosen for predictable behavior. They
are recommendations, not measured performance results or a universal optimum.
Distances are millimetres. Start with the correct switch model and spacer
configuration in Wootility. Do not select a third-party switch model merely to
expose a more aggressive setting.

Wooting's FPS guidance recommends shallow movement actuation, deeper jump and
ability keys, and Rapid Trigger on movement keys. Continuous Rapid Trigger has
little value at very shallow actuation and can start disabled. The same guide
warns that deeper spacebar actuation reduces accidental jumps. The settings
below use that principle but retain enough margin for resting fingers.

| Profile | Initial actuation | Rapid Trigger | Reasons and exceptions |
| --- | --- | --- | --- |
| Work | 2.0 on letters, numbers, punctuation, navigation; 2.5 on modifiers and Space | Off | Stable held shortcuts and fewer accidental presses. Keep familiar base layout. |
| FPS | 0.4 on WASD; 0.8 on Ctrl; 1.0 on Shift; 1.5 on ordinary abilities; 2.0 on Space; 2.5 on ultimate; 2.0 elsewhere | WASD only, release 0.15 and press 0.20 | Fast stop and repeat movement without applying hair-trigger behavior to chat, jump, and abilities. |
| Rhythm | 0.8 on the actual hit keys; 2.0 elsewhere | Hit keys only, release and press 0.20 | Repeated notes reset without a full return. Increase sensitivity distance if held notes drop or unintended repeated notes occur. |
| MOBA | 1.0 on QWER; 2.5 on D/F or other valuable cooldowns; 2.0 elsewhere | Off | Distinct presses and protected high-cost abilities. Use the game's real bindings rather than assuming every MOBA uses the same layout. |
| MMO | 1.0 on WASD; 1.5 on frequent skills; 2.5 on long cooldowns; 2.0 elsewhere | WASD only, release and press 0.25 | Responsive movement while skills and held modifiers remain predictable. |
| Strategy and management | 1.5 on common command keys; 2.0 elsewhere | Off | Deliberate command entry. Retain function keys and ordinary Ctrl, Shift, and Alt chords. |
| Driving | Analog A/D steering, W throttle, S brake; 2.0 on other keys | Off | Linear axis response first, then adjust against an in-game input meter. Use a separate analog profile. |

Wooting explains that Rapid Trigger changes the reset and reactivation point
according to movement, offers independent press and release distances, and can
apply per key. Larger distances require more movement. Rhythm games benefit
from repeated activation, but held notes still need deliberate release testing.
[Rapid Trigger guide](https://help.wooting.io/article/102-how-to-set-up-rapid-trigger).

Only four profiles can be onboard simultaneously. Choose the categories
actually needed and keep other profiles inactive. The installed selection is
Work, FPS, Driving, and Casual; the broader categories above are references. Export or duplicate a profile
before replacing an occupied slot. Four onboard slots do not imply that every
category can be simultaneously available from physical shortcuts.

### Advanced keys and layers

Leave Rappy Snappy and Snappy Tappy SOCD disabled in every general-purpose
preset. Rappy Snappy compares opposite-key depth; Snappy Tappy can select
last-input, absolute, or neutral priority. Wooting says both are prohibited in
CS2. A game-specific opt-in can be reasonable where the game and tournament
rules permit it, but one safe FPS preset avoids an accidental prohibited mode.
[Wooting's explanation and CS2 restriction](https://wooting.io/ja/post/rappy-snappy-tappy).
Valve separately documents kicks for hardware-assisted counter-strafing and
multiple player actions from a single input. DKS multi-action movement binds
therefore also require care.
[Valve's input policy](https://store.steampowered.com/news/posts/?appgroupname=Counter-Strike%3A+Global+Offensive&appids=730&enddate=1724194853&feed=steam_community_announcements).

Leave DKS disabled by default. It assigns actions at stages of press and
release; an optional offline single-player profile could assign walk at a
shallow press and sprint at a deeper press. This needs the game's actual walk
and sprint bindings and a release test, rather than a guessed global macro.
[DKS guide](https://help.wooting.io/article/99-how-to-use-dks).

Mod Tap emits different actions for a tap and hold. An optional work-only
Caps Lock tap for Escape and hold for Ctrl, with an initial 180 ms threshold,
can suit command-line editing. Preserve regular Ctrl and Escape keys while
learning it, and test fast overlapping chords before adopting it. Do not
change every modifier to Mod Tap or put it on gaming movement keys. The 80HE
already has dedicated arrows, so a 60HE arrow-key preset adds no benefit here.
[Mod Tap guide](https://help.wooting.io/article/98-how-to-use-mod-tap).

Leave Toggle off on action and movement keys. If needed, use Toggle only for
an explicit work navigation layer with a visible indicator and a convenient
exit key. Keep a normal momentary Fn layer for media controls, profile selection,
brightness, and Windows-key locking. Preserve factory Fn shortcuts unless a
replacement is tested. Advanced-key availability does not mean every feature
should be active in each profile.

### Analog mode and device-wide settings

Use No Gamepad for normal work and digital gaming if controller emulation is
unused. This avoids a phantom controller taking player-one assignment.
[Official disable procedure](https://help.wooting.io/article/76-how-to-disable-all-gamepads).
Driving needs a controller mode deliberately enabled, a compatible game,
and axis mappings. Map A/D to opposite halves of the steering axis, W to
throttle, and S to brake. Disable duplicate keyboard output only for mapped
analog keys, and keep menus, Escape, and profile switching usable.

XInput is not supported by Wooting on macOS. Linux XInput also has additional
driver considerations; Wooting's guide uses xboxdrv. Do not grant global input
group membership or add an unverified persistent driver just to advertise
analog support. Start with native HID or DirectInput compatibility where the
Linux game supports it, and verify axes, neutral values, simultaneous inputs,
and keyboard/mouse coexistence in that specific game.
[Gamepad modes](https://help.wooting.io/article/100-how-to-change-your-keyboard-gamepad-mode),
[Linux XInput guide](https://help.wooting.io/article/93-configuring-xinput-support-for-linux).

Tachyon mode synchronizes 80HE key scanning and USB polling for the advertised
8 kHz operation. Enable it for latency-sensitive gaming after checking USB
stability. Polling rate is a device-wide choice, so do not promise independent
rates for every onboard profile. [80HE performance specification](https://wooting.io/wooting-80he).
Use 1000 Hz as a compatibility fallback if 8000 Hz causes cold-boot detection
problems. Wooting explains that 1000 Hz uses USB Full-Speed and 8000 Hz requires
USB Hi-Speed. Changing ports can isolate motherboard controller issues.
[Official polling troubleshooting](https://help.wooting.io/article/325-keyboard-not-detected-on-startup-until-reconnected-8000).
Keep nKRO enabled for normal PC use; reduce it only if a BIOS or an application
has a confirmed compatibility problem.
[Wooting nKRO compatibility guide](https://help.wooting.io/article/106-how-to-use-your-wooting-keyboard-with-playstation-xbox-or-pc-bios-nkro-off).

Use restrained static RGB, with a profile color and brighter active game keys.
An initial brightness of 35 percent and a short idle sleep reduce distraction.
The Light Indicator can show the active profile without a host service. Keep
live CPU, volume, or Discord integrations optional because they need software
running on the host. A distinct work color helps identify a lingering gaming
profile after a session. Choose colors and brightness for readability; they
have no demonstrated typing-performance optimum in the reviewed sources.

### Work placement and personal tuning

Place the keyboard in front of the body, keep the mouse close enough to avoid
reaching, and adjust desk or chair height so shoulders are relaxed and wrists
align with forearms. Use the 80HE's lowest angle as a starting point, then
choose feet by wrist alignment rather than by a fixed universal tilt.
OSHA recommends avoiding keyboard feet that increase wrist bending.
[OSHA keyboard placement guidance](https://www.osha.gov/etools/computer-workstations/components/keyboards).
If a palm support is used, match the front keyboard height. Let the hands move
freely above it while typing and rest the heel of the palm, rather than the
wrist, between inputs.
[OSHA palm-support guidance](https://www.osha.gov/etools/computer-workstations/components/wrist-palm-support).

Evaluate one profile change at a time. Compare typing errors and shortcut
reliability over several ordinary work sessions. If resting fingers trigger
keys, raise those keys by 0.2 mm. If rapid repetition drops held inputs, increase
the RT release distance on the affected keys before changing unrelated keys.
For games, test movement stops, sustained holds, repeated taps, and simultaneous
inputs in practice mode before ranked play. The most sensitive possible setting
is not an evidence-backed default for every hand or game.

## Validation and limits of this follow-up

This follow-up reviewed first-party documentation on 2026-10-07 and compared
it with the earlier package and artifact investigation. Runtime observations
below come from the subsequent implementation. No keyboard firmware was
flashed. No throughput, latency, typing-error, ergonomic, or game-score
measurements ran.

The implementation subsequently tested a physical 80HE using Wootility 5.4.2
and firmware 2.14.0 on Linux. The editor detected the operating device at
`31e3:1402`, and the active user had read and write ACLs on every enumerated
Wooting hidraw interface. This ruled out missing normal-mode user access for
that session.

The editor's own reversible bootloader transition produced a device named
Wooting Restore at `31e3:140f` with a single `03:00:00` HID interface. USBGuard
blocked it. A temporary exact authorization allowed Wootility to connect to
the bootloader and reboot it into the normal keyboard firmware. This test
changed neither firmware nor stored profiles. It directly demonstrated the
missing update-mode authorization and the recovery path. The actual device
hash is retained in configuration, rather than copied into public prose.

Changing the controller mode from None to Xbox 360 changed the operating
identity to `31e3:1400`. USBGuard also blocked that identity until an exact
normal-mode rule authorized it. The resulting USB interface set included an
Xbox interface and HID interfaces. Linux attached xpad and enumerated a
joystick. These observations prove device and driver enumeration, not analog
compatibility in every game. The reviewed exact rules are maintained in the
[desktop USBGuard policy](../../hosts/nixos/desktop/local/security/usbguard.rules).

One-off inspection of the installed application's controllers established its
native schema version 15 export and import conversion. Generated exports went
through Wootility's own profile creation and save operations, followed by
controller reads of the keyboard. Assertions verified actuation, selected-key
Rapid Trigger, RGB, Tachyon, remapping, and disabled advanced keys for all four
profiles. Work was active at completion. This is verified application behavior
for 5.4.2, not a stable public API contract.

The chosen onboard set is Work, FPS, Driving, and Casual. Work uses 2.0 mm
actuation with Space and modifiers at 2.5 mm. FPS uses 1.5 mm generally, WASD
at 0.4 mm with release RT at 0.15 mm and press RT at 0.20 mm, Space at 2.0 mm,
Ctrl at 0.8 mm, Shift at 1.0 mm, Super at 3.5 mm, and Caps Lock at 2.5 mm.
Tachyon is enabled for FPS. Driving uses the left-stick steering and separate
trigger mappings described above, a linear response, and overrides keyboard
output only for those mapped keys. Casual uses 1.5 mm generally, Space at
2.0 mm, and Super at 3.5 mm. All retain normal modifiers and Fn profile
selection. Static RGB is 35 percent, with a global profile Light Indicator.
Rhythm, MOBA, MMO, and Strategy recommendations remain reference material;
they are not additional installed profiles.

The full desktop system build passed through `just os-build desktop`.
Firmware 2.14.1 was offered by the editor but was not flashed. The remaining
limits are firmware-flash verification, Linux background-service behavior under
the active compositor, game-specific analog input, and personal comfort and
performance measurements. Reversible bootloader reboot proves access to the
update transport but does not prove a firmware flash completed.

## Implication for this repository

The [desktop Wooting module](../../hosts/nixos/desktop/local/hardware/wooting.nix)
generates native profile exports from the reviewed layout and settings. It
exposes `system.build.wootingProfiles` and installs exports under
`/etc/wooting/profiles`. The [keyboard operating guide](../operations/wooting-keyboard.md)
describes profile selection and updating. Nix owns these assets; applying them
to the keyboard remains an explicit save operation in Wootility.

Keep system access in the desktop input and USBGuard modules, package ownership
in the existing Wootility module, and reviewed host-specific profile assets
beside the desktop configuration. Keep raw app inspection, device identifiers,
and original profile backups outside public documentation. Treat settings as
an explicit, reversible operation and retain a typing profile and factory
profile-selection shortcuts as a recovery path.

## Online profile comparison, reviewed 2026-10-07

This follow-up inspected actual share payloads rather than relying on profile
names or download counts. Wootility's current web application retrieves them
through `GET https://api.wooting.io/public/wootility/profiles?code=<CODE>`.
Thirteen public profiles returned JSON successfully. This observed endpoint is
not a documented stable API. Community attribution follows each uploader's
Wootabase page; it does not authenticate their identity or establish improved
typing accuracy or game performance. Older schemas and layouts require
transplanting selected settings into the reviewed 80HE layout.

| Source | Observed payload | Implication |
| --- | --- | --- |
| [Wooting recommended CS2 80HE](https://api.wooting.io/public/wootility/profiles?code=4143e5bad18d41e9e1b10715769e3a4f5d39) | Schema 15; general actuation 1.5 mm, WASD 0.7 mm, WASD RT 0.4 mm, Super 4.0 mm; no advanced keys or DKS | Supports deliberate ordinary keys and movement-only RT. Its Tachyon is off, although the accompanying guide recommends it on. |
| [Twistzz 80HE](https://api.wooting.io/public/wootility/profiles?code=1bd596e9066fbd984d1c0e089a97b0b3d3ba) | Schema 14; general actuation 1.3 mm, WASD 1.1 mm, WASD RT 0.3 mm; Space, left Shift, and Super 3.2 mm; Tachyon on; no advanced keys or DKS | Direct precedent for 0.3 mm RT and deeper accident-sensitive keys. Professional profiles need not use minimum actuation. |
| [jks 80HE](https://api.wooting.io/public/wootility/profiles?code=d43915b9ec117696830421c8ef34cd18d270) | Schema 15; WASD 1.5 mm with RT approximately 0.15 mm; Space approximately 3.0 mm; Tachyon on; no advanced keys or DKS | Illustrates deeper movement actuation with sensitive reset, rather than a universal preference for 0.15 mm. |
| [TenZ 80HE](https://api.wooting.io/public/wootility/profiles?code=28cf2e9f936cd72fed9bc326a36c49eaf3ea) | Schema 15; general actuation 1.0 mm, WASD and left Ctrl 0.4 mm; Space, Escape, Tab, and Caps Lock 3.0 mm; broad per-key RT, continuous behavior, and Rappy Snappy on opposing movement pairs | Useful actuation ideas, but unsuitable as an unchanged general FPS import because it enables Rappy Snappy. |
| [Just Typing, uploaded by xpzt](https://wootabase.com/profile/925e6d6655bfeab35c933303ff91543758da) | Schema 14, 80HE ANSI target; general actuation 1.6 mm, Caps Lock 3.0 mm; RT off; three Mod Tap entries and custom layers | Moderate actuation and RT off are plausible for work; custom modifiers and layers require individual review. |
| [Daily Typing Profile, uploaded by Sp4m](https://wootabase.com/profile/0d3c7e903f94278a8009c2e0eee5a352870e) | Schema 13, 60HE target; general actuation 1.0 mm; RT off; no advanced keys or DKS | An alternative typing preference without comparative accuracy evidence or a reason to overwrite the 80HE layout. |
| [GTA Driving and Flying, uploaded by shvin](https://wootabase.com/profile/0e5ea42f4a11f13b6518bc722c6f3b903a05) | Schema 14, 80HE ANSI target; WASD maps to steering and separate throttle/brake triggers; keyboard override on; RT off; additional flight mappings and shaped curve | Matches Driving's core axes and suppression of duplicate keyboard events. Flight mappings are game-specific. |
| [Trackmania 2020 Analog, uploaded by NocturnTaciturn](https://wootabase.com/profile/4d4c701db67762b81d43b117cfe61f265cdd) | Schema 10, Wooting Two target; W/A/D plus Space brake; keyboard override on; RT off; shaped curve | Supports dedicated analog steering; its brake key and curve should follow the game's bindings and input display. |

Wooting's [CS2 guide](https://wooting.io/post/wooting-cs2-guide-in-game-benefits-rapid-trigger-settings-and-pro-profiles)
supplies the CS2 profile codes above. It recommends WASD actuation between
0.4 and 0.7 mm and RT between 0.2 and 0.5 mm, explaining how 0.15 mm can
produce unwanted releases when finger pressure varies. The revised 0.3 mm
press and release distances fall within that range and match Twistzz's
inspected sensitivity. Keep RT limited to WASD, excluding held interaction
keys such as defuse. The accompanying
[Valorant guide](https://wooting.io/post/wooting-valorant-guide-in-game-benefits-settings-and-pro-profiles)
recommends 0.2-0.4 mm sensitivity and attributes the TenZ code, warning about
its Rappy Snappy setting. Professional profiles differ substantially in
actuation, reset sensitivity, and which keys use RT. Their settings are
examples rather than evidence of a universal optimum.

The [typing/gaming hybrid uploaded by FAT9L](https://wootabase.com/profile/2a7343916ff61e4ee1667ee94affe6463125)
uses global RT, 0.2 mm movement and Space actuation, several Mod Tap bindings,
and toggle layers. Its creator describes Apex-specific adjustments and
external desktop bindings. Preserve Casual's ordinary modifiers and stable
digital inputs rather than importing these specialized controls.

Keep Work at 2.0 mm initially. The typing profiles provide preferences but no
measured reason to favor 1.0 or 1.6 mm. Keep Driving's linear curve initially:
the inspected vehicle profiles share a shaped curve beginning at `(0,26)`,
but neither establishes its suitability across different vehicles and games.
Retain four profile shortcuts, restrained lighting, and disabled multi-action
features. Apart from changing RT to 0.3 mm, this comparison establishes no
further necessary change.

The downloaded profiles were inspected without writing them to the keyboard.
No typing-error, latency, comfort, or game-performance comparison ran. Native
readback of the revised installed FPS profile confirmed only its four WASD
keys have effective RT configuration, with Q and Space disabled. All four
installed profiles passed readback after the follow-up; the full desktop
build and activation passed and installed the updated generated exports.

## White-tint follow-up

Reviewed: 2026-11-05, Wootility 5.4.2 and 80HE firmware 2.14.2.

The local white-backlight comparison found pink-looking keycap legends and
greener exposed inter-key glow. Native readback showed the same RGB values
across the complete matrix, no RGB-effect layers, and the separate Light
Indicator disabled. This rules out an accidentally multicolored preset for
that capture; it does not identify a defective LED, a particular optical
component, or a firmware rendering algorithm.

A stronger green correction improved the pink cast but made the surrounding
glow objectionably green. One shared RGB drive cannot independently adjust
the light before and after it passes through keycap material. The final setup restores the factory ANSI typing profile and uses explicitly
requested RGB `220/245/255` at 20 percent brightness. No further automatic
white-balance correction is applied. This is a requested color setting, not a
calibrated neutral white; no colorimeter or color-temperature claim is made.

Hardware readback also exposed quantization: requested red/blue channels of
198 read back as 199. Tiny numeric adjustments can therefore produce the same
stored color. The official SDK's
[`encodeColor` and `decodeColor`](https://github.com/WootingKb/wooting-rgb-sdk/blob/7e091a0dbdbc3fb01b5e7f7e77b18a7548c595aa/src/wooting-rgb-sdk.c#L83-L98)
pack five-bit red/blue and six-bit green channels. The local readback confirms
rounding on this native profile path; the SDK source alone does not establish
the complete Wootility importer or closed-firmware processing. Confirm actual
stored colors when testing a small adjustment.

Wooting staff confirmed historical color-reproduction and calibration work in
[issue 111](https://github.com/WootingKb/wootility-issues/issues/111).
Original reports in [issue 138](https://github.com/WootingKb/wootility-issues/issues/138)
and [issue 182](https://github.com/WootingKb/wootility-issues/issues/182) describe
brightness-dependent tint and purplish white on earlier keyboards and software.
These are evidence of those reports, not proof of the cause on an 80HE running
2.14.2. No universal correction triplet or documented 80HE user white-balance
calibration control was established by the reviewed primary sources.

Judge lighting at the intended brightness, keycaps, ambient light, and seated
viewing angle. Wooting's [ABS-keycap description](https://wooting.io/product/wooting-etched-backlit-abs-keycap-set-black)
identifies transparent shine-through legends, but does not quantify their
spectral transmission. Optical filtering and LED variation remain possible
contributors, not measured diagnoses. A screen preview or screenshot does not
measure the light emitted through the physical keycaps. Do not use the screen
eyedropper to validate a stored color: a
[Wooting staff reply](https://github.com/WootingKb/wootility-issues/issues/339#issuecomment-3612044884)
explains that the eyedropper can sample a hover-darkened preview and recommends
right-clicking a key to retrieve its color.
