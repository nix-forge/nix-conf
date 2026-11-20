# Shared macOS and Linux keyboard workflow

The MacBook is the reference for modifier placement and application shortcuts.
The Wooting's **Mac Work** profile puts Command beside Space on both sides.
Control remains a separate modifier for terminal commands. Control+Option
manages windows and workspaces on both systems.

The configuration is prepared declaratively. Building or activating Nix does
not write onboard keyboard memory. The original Typing Profile export remains
available as a recovery reference.

## Key placement and firmware

Open the [interactive 80HE layout](../assets/keyboard/wooting-layout.html) to
switch between the main layer and the existing Fn layer. This is the ANSI
80HE layout, not an ISO/JIS or 80HE+ mapping.

| Physical position | Mac Work role | Native profile code | USB HID usage |
| --- | --- | --- | --- |
| Left Ctrl | Control | 99 | 0xe0 |
| Left Win | Option | 101 | 0xe2 |
| Left Alt | Command | 102 | 0xe3 |
| Right Alt | Command | 106 | 0xe7 |
| Right Ctrl | Option | 105 | 0xe6 |
| Existing Fn | Fn | 231 | Firmware layer key |

These profile codes were checked against the `wooting-usb` source shipped with
Wootility 5.4.2. They are not interchangeable with raw USB HID usage numbers.
Both native profile layers receive the same modifier meanings. Letters,
punctuation, lighting, actuation, Caps Lock behavior and navigation/media Fn
assignments are inherited unchanged from the reviewed typing export.

Right Control becomes Option; left Control stays available. No tap/hold timing,
home-row modifiers or macros are introduced. Match keycap labels to the table
using compatible keycaps. Changing a label alone does not remap the switch.

The [Nix profile owner](../../hosts/nixos/desktop/local/hardware/wooting.nix)
contains readable `modifiers` and `workRemaps` definitions. It transforms the
[existing native profile](../../hosts/nixos/desktop/local/hardware/wooting-typing.json)
in memory, preserving that file. There is no second manually maintained copy
of the complete JSON profile.

## Build and apply

Build the export bundle from the repository root:

```sh
nix build --out-link result-wooting \
  .#nixosConfigurations.desktop.config.system.build.wootingProfiles
```

The `result-wooting/` directory contains:

- `01-typing.json`: unchanged original typing settings.
- `02-mac-work.json`: generated schema 15 ANSI 80HE work settings.
- `layout.html`: key placement and Fn layer diagram.
- `README.md`: portable profile application instructions.
- `bin/wooting-mac-work`: publisher pinned to the generated work profile.

After a desktop activation, the same bundle is available at
`/etc/wooting/profiles/`. The original and work exports are desired settings,
not claims about the currently selected onboard profile.

**Wootility 5.4.2's ordinary Import Profile dialog accepts share codes, not this
native JSON.** Do not paste the JSON there or merely rename its extension.
Builds and activation do not upload profiles or write the keyboard.

Validate the generated profile locally, then explicitly publish it:

```sh
./result-wooting/bin/wooting-mac-work validate
./result-wooting/bin/wooting-mac-work publish
```

`validate` enforces the closed `ansi80he-typing-v2` contract before any network
or release-state operation. It checks known native keycodes, unique reviewed
coordinates, complete main-layer coverage, two layers with the dedicated Fn
key preserved, and a name of at most 30 UTF-8 bytes. Nested RGB, metadata,
analog, gamepad and lightbar fields are checked; unknown fields fail explicitly.
The export build runs this same offline validator, so unsupported Nix edits fail
before the work-profile bundle and its publisher wrapper are produced.

This contract is for the digital typing workflow: RT and Tachyon are disabled;
DKS, AKC, custom actuation, per-key RT, gamepad mappings and RGB effect lists
must be empty. RGB matrices require six rows of 21 explicit color/null cells;
the lightbar supports the reviewed optional solid Caps Lock indicator. Other
features require a separately reviewed contract and remain configurable through
Wootility. Their unsupported settings are rejected rather than dropped.

Actuation and sensitivity use explicit native 14-bit integer values `5..16383`.
Values `0..4` are rejected because Wootility 5.4.2 treats them as legacy
millimeters even in schema 15. Do not enter millimeter values in these native
fields. The [conversion audit](../research/wootility-80he-research.md#rea-audit-of-import-conversion)
explains the source evidence, supported subset and limits. Passing validation
does not establish compatibility with every firmware revision or persist settings
on the keyboard.

`publish` uploads the **complete profile** to Wooting's sharing service and
retrieves the returned code. It reports a verified code only when every native
profile field matches, ignoring only the demonstrated server-added `guid`.
The profile is retrievable by its code; publication is an intentional cloud
operation. This adapter follows the observed Wootility 5.4.2/schema 15 sharing
endpoint, which is not a documented stable public API. See the
[import research](../research/wootility-80he-research.md#native-profile-import-follow-up).

In Wootility, choose **My Profiles → Import Profile**, paste the verified code,
and import it. Review the profile and intended onboard destination, then use
**Save to Keyboard**. Close Wootility and verify both layers after reconnecting.
The publisher does not open Wootility, select a slot or write device memory.
The helper emits the normal import instructions instead of a deeplink: the
protocol route does not perform the same modal checks and remains unvalidated.

After host activation, `wooting-mac-work` is also installed as a command.
For another native file, the underlying `wooting-profile-share` binary is
available from `system.build.wootingProfileShare`; it requires `--profile FILE`
and deliberately accepts only the reviewed schema 15 ANSI 80HE typing subset.

### Reuse and recover a publication

A private release record stores the desired JSON, canonical-content SHA-256,
adapter version, candidate code and verification state. On Linux its default
location is `$XDG_STATE_HOME/wooting-profile-share`, or
`$HOME/.local/state/wooting-profile-share` when that variable is unset. The
standalone macOS helper uses `$HOME/Library/Application Support/wooting-profile-share`
when `XDG_STATE_HOME` is unset. `--state-dir DIR` selects a dedicated directory;
it must have mode `0700`. Records use mode `0600` and atomic replacement.

Repeated `publish` for unchanged content retrieves and verifies the retained
code without uploading again. Changed content gets its own record. To check a
retained code, or adopt a known code for identical complete settings:

```sh
./result-wooting/bin/wooting-mac-work verify
./result-wooting/bin/wooting-mac-work verify --code CODE
```

A durable intent is saved before POST and a candidate code before GET. If an
upload times out or is interrupted, rerunning cannot silently create another
profile. If a candidate was received, rerun `verify`; if its record could not
be saved, recover the code printed on stderr with `verify --code CODE`.
If no code can be recovered, `publish --republish` explicitly authorizes another
upload and archives the previous record. Retain the release directory as well
as the native JSON. All network operations have bounded timeouts; redirects
and automatic retries are disabled. A read-back mismatch or service failure
returns an error without claiming a verified result.

### Check what Wootility imported

Import through **My Profiles → Import Profile** on the intended 80HE, then use
Wootility's **Share** action on that imported profile. Compare the newly returned
code with the desired Nix profile:

```sh
./result-wooting/bin/wooting-mac-work compare-import --code CODE_FROM_WOOTILITY
```

This command only retrieves and compares content; it never uploads, writes
release records or accesses the keyboard. Supply the code from the profile
**after import**, rather than simply reusing the publisher's code. The command
cannot authenticate that the supplied content actually passed through Wootility.
A compatible native re-export file can instead be checked entirely offline:

```sh
./result-wooting/bin/wooting-mac-work compare-import --imported reexport.json --json
```

`import-content-matches` means both inputs passed the typing contract and matched
after a narrow normalization: expected description replacement by `~`, optional
server `guid`, absent white scroll/num-lock defaults, absent/null secondary RT
sensitivity and ordering of unique sparse remap entries. Remap **layer order**
and every binding, actuation value, color and lightbar setting remain significant.
An unexpected difference fails with its JSON pointer. Cloud publication retains
its separate, exact complete-JSON comparison; it never uses these normalizations.
The JSON result identifies `validation_contract` separately from the sharing
`adapter`, so existing content hashes and interrupted-publication records remain
usable and are revalidated under the stronger contract.

A controlled private replay using the original 5.4.2 converter and serializer
matched the current profile under this comparison. It did not start the full
app or exercise device/firmware normalization. After app review, save deliberately
and verify persistence by reconnecting. The comparison does not attest either
of those actions.

### Manual fallback

If the service or version-specific adapter stops working:

1. Back up the current keyboard settings and preserve the existing typing
   profile in Wootility's profile library. Use that profile as the starting
   point for a work copy named **Mac Work**.
2. In Remap, change the four positions listed above: Left Win → Left Alt,
   Left Alt → Left Windows, Right Alt → Right Windows, Right Ctrl → Right Alt.
   Wootility may show Option/Command instead of Alt/Windows on macOS.
3. Check the Fn layer too. Its explicit modifier overrides must use the same
   roles; set the left Win position to Left Alt, left Alt to Left Windows,
   right Alt to Right Windows, and right Ctrl to Right Alt there as well.
   Keep the actual Fn key unchanged.
4. Save to the keyboard. Close Wootility and verify both Command keys,
   Control, Option and Fn combinations. The onboard settings should persist
   after reconnecting the keyboard.

The UI fallback applies the same modifier transformation. Wootility edits do
not update the Nix source. For repeat imports without the adapter, use
Wootility’s Share action after configuring and reviewing that work profile.

Build the desktop closure with `just os-build desktop` on the desktop host.
From another host use `just desktop-build`. Activate deliberately after
reviewing the build, using the corresponding switch/deploy command from
[AGENTS.md](../../AGENTS.md). Apply the Mac home/system configuration through
the normal Darwin deployment workflow as well. No activation is needed just
to inspect or build the profile exports.

When transitioning, activate the host shortcut configuration before selecting
the new firmware profile. Existing Control-based Linux application shortcuts
remain available. Then select the Mac Work profile and use it on both OSes.
Leave the Mac's per-device Command/Option overrides at their defaults; a second
swap would undo the onboard mapping. The MacBook built-in modifiers stay native.

## Everyday shortcuts

| Shortcut | Behavior |
| --- | --- |
| Command+C / V / X | Copy / paste / cut in supported GUI applications |
| Command+S / F / A | Save / find / select all where the application supports it |
| Command+Z / Shift+Command+Z | Undo / redo |
| Command+Left / Right | Line start / end in supported text fields |
| Option+Left / Right | Move by word |
| Shift plus the navigation combinations | Extend selection |
| Option+Backspace / Delete | Delete previous / next word in supported text fields |
| Command+Backspace | Delete to line start; Nautilus instead moves selected files to Trash |
| Command+Space | Linux launcher / macOS Spotlight |
| Control+Command+Q | Lock the session |
| Command+Shift+3 / 4 | Linux full/region screenshot; native macOS screenshot |
| Command+Tab | Linux MRU window switcher / native macOS application switcher |

Native Linux and macOS menus may show different shortcut labels. A translated
shortcut does not rewrite an application's menu. In browsers, Command+T/W and
Shift+Command+T manage tabs; Command+L selects the address. Command+[ / ] goes
back/forward, and Shift+Command+[ / ] changes tabs. Command+1–9 selects browser tabs. Unknown shortcuts pass through.

The initial Linux xremap allowlist contains Firefox/Zen/Chrome/Chromium/Helium,
Nautilus, Signal and Discord. Rules are deliberately application-specific:
Nautilus keeps ordinary Return intact so rename/search dialogs still work.
Games, virtual machines, remote desktop clients, terminals, IDEs and unknown
applications receive no generic translation. Browser-hosted remote terminals
cannot be distinguished from other tabs by app ID; use native Control shortcuts
there or stop the remapper for that session.

## Terminal and VS Code behavior

Ghostty handles Command clipboard actions natively. Command+C without a
selection does not become Control+C. Control+C/D/Z/R remain terminal
interrupt/EOF/suspend/history shortcuts. Command+T/N/W opens a tab/window or
closes the current tab, Command+Q quits Ghostty, and Command+F opens its search.
Option+arrows send Alt+B/F to the shell, while Command+Left/Right sends
Control+A/E. These require the shell/TUI to implement the corresponding
navigation; terminal selection and GUI selection are different operations.
Command+Up/Down scrolls the terminal history. Option+Backspace emits Control+W
and Command+Backspace emits Control+U, matching the existing Mac policy;
line-editor behavior can vary.

VS Code handles Linux Meta/Command shortcuts natively, with separate
editor/input and integrated-terminal conditions. Command+C/V in its terminal
copies/pastes; an empty selection does not send SIGINT. Command+W closes the
active editor or terminates the focused terminal, following the respective
application context. Command+P opens files, Shift+Command+P opens commands,
Command+T searches workspace symbols, and Command+E retains this repository's
custom explorer action. Both Control+S and Command+S retain the existing
format-then-save behavior where its original conditions apply. Control-based
Linux defaults remain available.

## Window and workspace management

| Shortcut on both systems | Action |
| --- | --- |
| Control+Option+H / J / K / L | Focus left / down / up / right |
| Control+Option+Shift+H / J / K / L | Move the focused window |
| Control+Option+1–9 | Select a numbered workspace |
| Control+Option+B/C/D/M/N/P/T/E/A/S/Z | Select the corresponding named workspace |
| Shift plus a workspace shortcut | Send the window there without following |
| Control+Option+Enter | Open Ghostty |
| Control+Option+Shift+F | Toggle fullscreen |
| Control+Option+Shift+Space | Toggle floating |

Rift's additional resize, layout and service-mode commands also gain Control.
Control+Option+Tab returns to the previous workspace on both systems; it does
not replace Command+Tab.

Linux shell-only controls use **Control+Option+Command**: V opens clipboard
history, S opens the control center, comma opens shell settings, E opens the
file manager, and N controls notifications when that notification feature is
selected. The alternate Linux launcher uses Control+Option+Command+Space.
These avoid stealing app shortcuts and the named workspace family. Wallpaper
rotation uses Control+Option+Shift+W. Dictation keeps Option+Space for
push-to-talk and uses Control+Option+Shift+X to cancel, freeing workspace D. Linux also retains Control+Option+Q to
close a compositor window; this is not an implementation of macOS app quit.

Hyprshell switches individual windows in MRU order. It does not claim to
reproduce macOS application grouping or Command+backtick cycling. macOS
quit/hide/minimize lifecycle semantics remain native; Linux app quit is not
implemented as a global forced close.

Both keyboards expose ordinary F1–F12 without Fn after the Mac system setting
is applied. Hardware-specific Fn/media labels still differ. Wooting's firmware
Fn does not become Apple's Globe key.

## Remapper ownership and recovery

The [home module](../../modules/home/keyboard/macos-shortcuts.nix) owns the
xremap Hyprland user service and generated YAML. It uses the version already
pinned in nixpkgs; no additional flake input or mutable package installation is
required. The [host device-access module](../../hosts/nixos/desktop/local/hardware/keyboard.nix)
grants active-seat access to the supported Wooting keyboard events and uinput
without adding the login user to the broad input group. System/consumer-control
and mouse interfaces are excluded from capture. No key-triggered shell commands
are allowed, and window-title logging is disabled.

The service belongs to the graphical session, starts on login and watches for
keyboard hotplug. It retains open input descriptors while running, including
while the session is locked. This is trusted input-handling code; active-seat
ACLs alone do not prove descriptor revocation at lock. Unknown applications
have no fallback translations. Do not enable another evdev remapper over the
same device.

Stop or restart it from a terminal or SSH:

```sh
systemctl --user stop macos-shortcuts.service
systemctl --user restart macos-shortcuts.service
journalctl --user -u macos-shortcuts.service -b
```

For persistent rollback, set `keyboard.macosShortcuts.enable = false` in both
home profiles and rebuild. This restores the old Linux desktop shortcut family;
restore the original hardware modifier layout too. Rift's Control+Option
bindings and the Mac F-key preference are explicit target settings: revert
those separately if returning completely to the former arrangement. Stopping
the remapper alone leaves the new compositor shortcuts and firmware layout in
place. Keep a second ungrabbed keyboard or SSH access for recovery.

## Validation

Evaluation and static checks do not establish everyday comfort or live keyboard
behavior. After applying, check both Command keys, Fn+modifiers, copy with and
without a selection, editor/terminal focus, navigation and selection, browser
and file-manager dialogs, screenshots, switching, hotplug, suspend/resume,
lock/unlock and service stop/restart. Check both local and SSH/tmux/TUI terminal
use. Test real application IDs before expanding the allowlist.

Implementation validation on the Linux desktop (2026-11-17): the actual Linux
home settings and Darwin system derivation evaluated; Ghostty and Hyprshell
accepted the generated native settings; the Wooting export built and retained
the unchanged original profile and non-modifier settings; the udev rules passed
`udevadm verify`; xremap 0.15.18 built and accepted the generated YAML via
`--validate-config`. System and home assertions passed, and disabling the
feature restored the original numbered workspaces and alternate launcher.
Formatting and unused-binding checks passed. Statix reported existing repeated-
attribute style warnings in the independently modified wallpaper module; those
unrelated edits were preserved. A fresh review identified dictation cancellation and disabled-
feature launcher conflicts, which were corrected. No system activation or
onboard programming ran. Native Darwin execution, hardware behavior and daily
use remain unverified.

The full desktop build and aggregate repository checks were attempted but
stopped after repeated automatic garbage collection below the host's configured
free-space threshold. They are not recorded as passing. The small export and
remapper validation builds use no desktop system closure. The interactive HTML
was rendered in the conversation; automated screenshot preview was unavailable
because the host browser dependencies were missing.
