# Consistent keyboard placement and shortcuts on macOS and Linux

Reviewed: 2026-11-17. Scope: MacBook built-in keyboard, Wooting 80HE,
NixOS/Hyprland, Rift, Ghostty, and VS Code. Research and source inspection;
no keyboard programming, remapper installation, build, or activation performed.

Implementation follow-up: see the [shared keyboard operating guide](../operations/keyboard-workflow.md)
for the implemented configuration, export application and validation limits.
The source observations below describe the pre-implementation investigation.

## Answer

Use macOS as the reference for everyday shortcuts. Put Command immediately
beside Space on the external keyboard, retain a separate Control key, and
translate selected Linux shortcuts according to the application. Prefer native
application bindings where context matters; use one Linux remapper for the
remaining applications. Keep window-manager commands out of the Command
shortcuts used by applications.

For this repository, the recommended pilot is **Wootility modifier placement +
native macOS behavior + native Ghostty/VS Code bindings + xremap on Linux**.
This is an engineering recommendation, not a measured universal best layout.
Toshy is the strongest ready-made alternative for broad Mac-style behavior,
but its NixOS integration carries material experimental-status qualifications.

Success means the same finger movement performs the same common action. It
does not require identical menu labels, identical window models, or rewriting
every application's shortcuts.

## Findings and sources

### Physical placement

Use these roles on the Wooting's left bottom row, moving toward Space:

| Current physical position | Proposed role | HID modifier |
| --- | --- | --- |
| Left Ctrl | Control | Left Control |
| Left Windows/Super | Option | Left Alt |
| Left Alt, beside Space | Command | Left GUI/Super |

On the right, put Command beside Space and Option outside it where the actual
80HE layout permits; retain access to Control and the firmware Fn key. Inspect
the exact right-hand layout before choosing which extra modifier to replace.
Keycaps label the roles; firmware changes the signals. Moving caps alone does
not change behavior. Use compatible caps from the same row/profile.

[Wooting documents both a per-device macOS modifier swap and an onboard
Option/Command swap](https://help.wooting.io/article/95-swap-around-option-and-command-key-on-mac-osx).
Choose the onboard swap for a work profile used on both operating systems:
Linux then receives Super at the intended Command position too. Leave the
macOS per-device modifier overrides at their defaults for that profile, and
omit any duplicate Linux modifier swap. Wooting explicitly notes that an
onboard swap also changes Super/Alt placement on Linux.

The MacBook's extra Fn/Globe key and different dimensions prevent exact
geometry matching. Match adjacency to Space and modifier order. Keep letters,
punctuation, Caps Lock and typing actuation unchanged during the first pilot;
this isolates the shortcut change from other adaptations. Confirm ANSI/ISO and
input-source settings before moving punctuation. Wooting's general advice
about backtick/backslash is not a reason to swap them on a correctly detected
ANSI keyboard.

The existing [keyboard operating guide](../operations/wooting-keyboard.md)
records a factory-like typing layer and a useful firmware Fn navigation layer.
Back up that export before a future change. A dedicated Mac-like work profile
is preferable to rewriting gaming controls or applying different work profiles
on every OS switch.

### Shortcut roles and proposed behavior

Apple distinguishes Command, Option and Control and documents its standard
[shortcut families](https://support.apple.com/en-us/102650). Use the following
as a bounded initial contract, then test actual applications:

| Physical shortcut on both systems | Intended action | Linux owner/translation |
| --- | --- | --- |
| Command+C / V / X | Copy / paste / cut | GUI: application's native action or matching Ctrl shortcut; terminal cut is not assumed |
| Command+S / F / A | Save / find / select all | Native app binding or selected GUI translation |
| Command+Z / Shift+Command+Z | Undo / redo | App-specific; Linux redo is not uniformly Ctrl+Shift+Z |
| Command+T / W / Shift+T | New / close / reopen tab | App-specific bindings |
| Command+L | Browser address field | Browser translation; remove Linux lock conflict |
| Option+Left / Right | Move by word | Text fields: Ctrl+Left / Right; terminal handled separately |
| Command+Left / Right | Start/end of line | Text fields: Home / End where verified |
| Command+Up / Down | Start/end of document | Text fields: Ctrl+Home / End where verified |
| Shift plus navigation above | Extend selection | Explicitly test selection and held-key repeat |
| Control+C / D / Z / R | Terminal interrupt / EOF / suspend / history | Preserve shell/TUI behavior |
| Command+Space | Launcher | Desktop binding, excluded from app translation |
| Control+Command+Q | Lock session | Desktop binding, avoiding Command+L |

Home/End semantics, paragraph navigation and deletion vary between widgets and
editors. Command+Backspace should use a native delete-to-line-start action
where possible, not a universal guessed key sequence. The current Ghostty Mac
configuration emits Ctrl+U, which must be tested against the chosen shell:
line-kill behavior is not identical in every line editor.

### Native bindings where the application understands context

Ghostty exposes native
[clipboard and terminal actions](https://ghostty.org/docs/config/keybind/reference).
Give its Linux build Super+C and Super+V bindings for clipboard operations,
then exempt Ghostty from generic GUI translation. Preserve Control sequences
for local commands, SSH, tmux, Vim and other TUIs. Set additional terminal
navigation deliberately: Option is already configured as Alt on macOS, so
terminal navigation need not follow GUI word-navigation translations.

VS Code supports conditional bindings through
[`when` clauses](https://code.visualstudio.com/docs/configure/keybindings).
Its [integrated terminal](https://code.visualstudio.com/docs/terminal/basics)
shares the editor's application identity. An external remapper cannot infer
editor focus versus terminal focus from the app ID alone. Prefer native Linux
Super bindings with appropriate editor/terminal conditions, and exempt VS Code
from generic translation. Review existing save/format commands when adding
these bindings so the intended save sequence remains authoritative.
The [default shortcut reference](https://code.visualstudio.com/docs/reference/default-keybindings)
shows additional platform differences that a blanket Cmd-to-Ctrl rule misses.

Begin external translation with an allowlist of GUI applications, such as the
actual browser IDs observed locally. Unknown applications should pass through
rather than receive terminal-unsafe guesses. Native bindings also improve
shortcut discoverability; translated Linux menus will often still display Ctrl.
Modifier-click gestures are a separate contract: configure editor multi-cursor
and test browser link opening explicitly before claiming matching mouse use.

### Desktop shortcuts must release Command

Local source inspection found substantial collisions:

| Existing source | Current behavior conflicting with a Command role |
| --- | --- |
| [Workflow](../../modules/home/desktop/workflow.nix) | Super+arrows/HJKL, numbers, Q and F manage windows/workspaces |
| [Noctalia](../../modules/home/desktop/noctalia.nix) | Super+V, S and comma open shell panels/settings |
| [Idle](../../modules/home/desktop/idle.nix) | Super+L locks the session |
| [Applications](../../modules/home/desktop/applications.nix) | Super+E opens the file manager |
| [Rift configuration](../../homes/macbook-pro-m4/local/rift/config.toml) | Option+HJKL and numbers manage windows/workspaces on macOS |

Move the relevant desktop bindings together before enabling translation.
Otherwise a remap can suppress a desktop action or an unhandled Command chord
can unexpectedly manage a window. Assign each chord to exactly one owner.

For a clean long-term scheme, use **Control+Option** for shared window/workspace
commands, with Shift adding move-window behavior: Control+Option+HJKL to focus,
Control+Option+Shift+HJKL to move, and Control+Option+1–9 to change workspace.
Use only the shared workspace set initially; document extra workspaces
explicitly. These are proposed bindings, subject to local conflict checking.
Bare Option+HJKL already has an owner in Rift and can interfere with Option
character entry or terminal Alt commands; adding Control frees bare Option.
Check [macOS VoiceOver use](https://support.apple.com/en-ca/guide/voiceover/vo2681/mac)
before adopting its Control+Option modifier family.
Keeping existing Option-only tiling shortcuts on both systems is a smaller
migration, but accepts those conflicts.

Command+Tab needs a separate choice. Native macOS switches applications and
Command+backtick switches windows of an application. A Linux window switcher
may instead cycle individual windows. Choose application grouping where the
installed switcher supports it, or document the different behavior. Do not
bind Command+Tab to workspace-back-and-forth. Likewise, Command+Q quits an
application on macOS; a compositor's close-window action does not reproduce
that lifecycle. Keep Command+W as the first close shortcut to standardize and
leave quit/minimize/hide as explicit follow-up decisions.

### Remapper selection

| Candidate | Evidence | Assessment for this setup |
| --- | --- | --- |
| xremap | [App/device rules](https://github.com/xremap/xremap), [dedicated Hyprland backend](https://github.com/xremap/xremap/blob/master/doc/development/install_from_source.md), [Nix modules](https://github.com/xremap/nix-flake) | Recommended bounded pilot: explicit, inspectable mappings; Mac semantics must be specified |
| Toshy | [Mac-style behavior and Hyprland context support](https://github.com/RedBearAK/toshy), [Nix integration status](https://github.com/RedBearAK/toshy/blob/cdeae5e54ba2f48acb138c4d34c73b808cae88b6/nix/README.md) | Broadest ready-made behavior; investigate when custom rules become burdensome |
| keyd | [System remapping, layers and application mapper](https://github.com/rvaiya/keyd) | Good hardware/layer tool; adds context integration work for this GUI-focused goal |
| Kanata | [Layers and cross-platform customization](https://github.com/jtroo/kanata), [macOS driver/permission requirements](https://github.com/jtroo/kanata/blob/main/docs/setup-macos.md) | Better fit for substantial ergonomic layers; cross-platform engine alone does not unify app semantics |
| Karabiner-Elements | [macOS remapping capabilities and limits](https://karabiner-elements.pqrs.org/docs/getting-started/features/) | Optional for a later shared navigation layer; unnecessary for the initial Mac-native scheme |

Toshy's main README announces functional NixOS support, while its dedicated
Nix README labels the integration experimental and untested on real NixOS
hardware. It also retains a manually installed user-files/services layer.
These conflicting maturity signals justify a pilot, not a blanket statement
that NixOS is unsupported or production-proven. Its extensive application rules
are valuable reference material even if another engine is selected.

For xremap, select the **Hyprland (`hypr`) backend**, or a full build with that
backend selected. The reviewed Nix module documents `services.xremap.withHypr`
for enabling this integration. Do not infer support from a wlroots-only build. Its
[changelog](https://github.com/xremap/xremap/blob/master/CHANGELOG.md) records
why the Hyprland client was restored after wlroots ceased working for it.
The [Nix HOWTO](https://github.com/xremap/nix-flake/blob/0c48328034c0a6527a0e385555629b65c7db7a8b/docs/HOWTO.md)
and exact pinned module must determine service options; do not paste a
historical `withWlroots` example into this compositor configuration.

### Reliability, permissions and ownership

An evdev/uinput remapper has authority to read and inject keyboard input.
[xremap's permission documentation](https://github.com/xremap/xremap/blob/master/doc/running_without_sudo.md)
explicitly describes the broad input-group tradeoff and lock-screen/multi-user
implications. Run the app-aware component with the graphical user's compositor
context. Select the intended device, exclude virtual output, and plan device
access deliberately rather than silently granting all applications permanent
input access. Session service lifetime alone does not prove lock-screen
suspension or removal of already-open input descriptors.

Use only one active evdev grabber. Firmware should own modifier placement;
the remapper should own the selected GUI translations; applications should own
context-sensitive actions; the compositor should own desktop commands.
Generate reviewed rules from Nix, pin dependencies, and use normal service
supervision. Avoid shell subprocesses for routine key translation and avoid
retaining keystroke/window-title debug logs.

Keep a known working hardware profile and a second, ungrabbed keyboard or SSH
recovery path. Verify stopping the service restores input, including after
unplug/replug and after modifiers are released. A bypass binding inside the
remapper cannot recover a process that has hung. Scope translation away from
games and remote desktop/VM clients until their intended input contract is
chosen; shortcuts translated before entering a guest cannot be recovered by
that guest.

Fn is optional convenience, not the shared modifier foundation. Wooting offers
[firmware layers](https://wooting.io/quickstart/keyboard/wooting-80he/prebuilt).
Karabiner explains why many
[non-Apple Fn keys do not generate host events](https://karabiner-elements.pqrs.org/docs/getting-started/features/).
Keeping the existing Wooting layer is reasonable, but matching it on the
MacBook later would be a separate software-remapping project. Similarly,
align the top-row F-key/media preference explicitly; identical firmware Fn
behavior and Apple Globe features are not assumed.

## Validation and limits

Inspected the current working tree, including both selected home profiles,
Hyprland desktop bindings, Rift configuration, Wooting operating notes,
Ghostty settings and VS Code bindings. These are source observations, not a
readback of either running system. The repository has unrelated uncommitted
changes; the recommendation describes the inspected files rather than claiming
they match HEAD alone. Primary sources were retrieved on the review date;
moving upstream branches are not deployment pins.

No runtime keyboard, compatibility, performance or comfort tests ran. No claim
of identical behavior across all applications, boot screens or input sources
is established. A future pilot should verify:

1. Wooting modifier signals and MacBook finger positions; both modifier sides;
   punctuation, input source and top-row preference.
2. GUI copy/paste/save/find/undo/redo, navigation, selection and repeat in real
   browsers, GTK/Qt applications and Electron applications; clipboard copy with and
   without a selection must never unexpectedly interrupt a terminal process.
3. Ghostty and VS Code terminal clipboard actions while Control+C/D/Z/R still
   reach the shell, including SSH, tmux and editor TUIs.
4. Command chords freed from every compositor/shell module; launcher, locking,
   workspace and window switching perform the intended action exactly once.
5. Login, lock/unlock, logout, suspend/resume, hotplug, service restart/stop,
   modifier release, games and guest/remote input exclusions.

## Implication for this repository

Implement in stages after choosing to proceed: back up and establish physical
placement, resolve desktop conflicts, configure Ghostty/VS Code natively,
then pilot a small xremap allowlist. Expand only after checking the actual
application behavior. Keep the existing work profile recoverable throughout.
Toshy becomes the alternative if maintaining the required application-specific
semantics costs more than validating and maintaining its NixOS integration.

A full desktop closure build belongs on the desktop host under the repository's
build-placement rules; research alone does not need one. Programming the Wooting
and activating OS changes remain separate implementation actions.
