# Wooting 80HE typing setup

The keyboard has one onboard **Typing Profile**, restored from Wootility's
factory ANSI settings. Standard main-layer key positions, modifiers, and
factory typing actuation are preserved. The Fn layer adds work shortcuts. The
custom macOS modifier swaps and per-key actuation changes were removed. Rapid
Trigger is off in this profile.
The factory Rapid Profile was moved to Wootility's inactive library.

The main layer uses static RGB **228/255/228**, at 20 percent brightness.
Caps Lock matches the surrounding keys when off and changes to soft lavender
**210/180/255** only when enabled.
The device can round RGB channels during storage; the requested values remain
in the export. No further white-balance compensation is applied. The legends
and the surrounding glow can have different tints; see the
[lighting research follow-up](../research/wootility-80he-research.md#white-tint-follow-up).

The light bar stays dark unless Caps Lock is enabled. Its final three LEDs then
show a steady white-balanced indicator (RGB 220/255/220 at the profile
brightness). The separate bar correction reduces its purplish tint. The profile does not inherit
global effects, so the colored profile indicator is suppressed. This uses the
onboard Caps Lock preset and needs no background service.

The keyboard works with Wootility closed. Firmware 2.14.2 is installed. The
restored device retains NKRO, No Gamepad, and normal high-speed keyboard polling.
No custom typing macros or modifier remaps are installed. Actual typing comfort
and macOS application behavior still need ordinary use on the target computer.

## Function layer

Hold the existing **Fn** key to use these shortcuts. Normal F1–F12 keys remain
available without Fn. Modifiers combine with navigation as usual.

| Hold Fn and press | Action | Layer lighting |
| --- | --- | --- |
| I / J / K / L | Up / Left / Down / Right | Pale blue |
| U / O | Home / End | Pale blue |
| Y / H | Page Up / Page Down | Pale blue |
| Backspace | Forward Delete | Pale blue |
| Left / Right arrow | Home / End | Pale blue |
| Up / Down arrow | Page Up / Page Down | Pale blue |
| F5 / F6 | Keyboard backlight down / up | Near-white |
| F7 / F8 / F9 | Previous track / play-pause / next track | Lavender |
| F10 / F11 / F12 | Mute / volume down / volume up | Lavender |

Fn lighting appears only while Fn is held. Other keys dim to RGB 32/32/32;
the Fn key is pale blue and the inactive Caps Lock key dims with its neighbors.
Its active indicator color remains lavender. Lighting is
static, with no animated effects. Profile switching and Key Lock shortcuts were
removed from this layer. Home/End send standard keyboard codes; their exact
behavior depends on the macOS application. The layer and lighting are stored
onboard and work without a background service.

## Ownership and reapplication

The [host module](../../hosts/nixos/desktop/local/hardware/wooting.nix) installs
one native schema 15 [typing export](../../hosts/nixos/desktop/local/hardware/wooting-typing.json)
at `/etc/wooting/profiles/01-typing.json`. Nix owns this desired export, Wootility
installation, session-scoped HID access, and the exact
[USBGuard identities](../../hosts/nixos/desktop/local/security/usbguard.rules).
Wootility writes onboard storage; activation does not reprogram the keyboard
at login or boot. Wootility edits do not automatically change the Nix export.

```sh
workstation-task nix build --no-link --print-out-paths \
  .#nixosConfigurations.desktop.config.system.build.wootingProfiles
```

Wootility 5.4.2's normal Import Profile dialog accepts share codes rather than
pasted JSON. Applying native JSON requires a compatible workflow. The local
setup used version-checked private automation, a complete save, and readback
after a keyboard reboot. Back up settings before reset or programming.

## Recovery

Keyboard-only, Xbox, and firmware-restore USB identities are authorized
separately with observed descriptor hashes and exact interfaces. Replacements
and firmware changes can require new identities. Check USBGuard first if the
keyboard is not detected, then check the active session's HID ACL. Run
Wootility as the ordinary desktop user.

Wooting documents holding **Pause + Right Arrow** while reconnecting an 80HE
to enter restore mode. Restore can reset settings; follow the
[official restore guide](https://help.wooting.io/article/90-how-to-restore-reset-my-wooting-one-or-wooting-two-flaretech).
