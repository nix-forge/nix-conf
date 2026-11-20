# Wooting 80HE Mac Work export

<!-- These sibling links resolve in the generated wootingProfiles output. -->
<!-- rumdl-disable MD057 -->
Open [layout.html](layout.html) to see both keyboard layers. The generated
[02-mac-work.json](02-mac-work.json) is a native schema 15 ANSI 80HE profile.
[01-typing.json](01-typing.json) preserves the original typing settings.
<!-- rumdl-enable MD057 -->

Wootility 5.4.2's ordinary Import Profile dialog accepts cloud share codes,
not native JSON. Do not paste this file there or rename its extension.
No cloud upload or automatic onboard write is performed by Nix.

The bundle includes a command pinned to `02-mac-work.json`. From this directory:

```sh
./bin/wooting-mac-work validate
./bin/wooting-mac-work publish
```

`validate` enforces the reviewed `ansi80he-typing-v2` subset: known native
keycodes, unique reviewed coordinates, complete main mapping, two layers with
Fn preserved, 30-byte UTF-8 names and closed nested structures. The export
build runs this validator before producing the work-profile bundle. Unknown fields
and unreviewed advanced features fail with a field-specific error. Digital input
must stay enabled; RT/Tachyon, advanced keys, custom/per-key actuation, gamepad
mappings and RGB effects are unsupported here. Configure those through Wootility
until their contracts are reviewed. Native actuation/sensitivity values must be
integers in `5..16383`; `0..4` triggers a legacy-unit migration and is rejected.
RGB requires six rows of 21 color/null cells per matrix; the reviewed solid
Caps Lock lightbar indicator is supported. Firmware limits still require app review.

`publish` deliberately uploads the complete profile to Wooting's sharing
service. It prints a verified share code only after retrieving and comparing
all settings, ignoring only server-added `guid`. In Wootility choose
**My Profiles → Import Profile**, paste that code, review the profile and
onboard destination, then **Save to Keyboard**. Close Wootility and check both
layers after reconnecting. No command writes keyboard memory.

After importing, use Wootility's **Share** action on the imported profile and run:

```sh
./bin/wooting-mac-work compare-import --code CODE_FROM_WOOTILITY
```

Or compare a compatible native re-export offline with `compare-import --imported
reexport.json`. This is a separate content check, with no upload, release-state
write or device access. It allows only the reviewed description/identity/default
and sparse-remap ordering differences, preserving layer order and settings.
It cannot prove that a supplied code/file actually came from an app import.
Cloud verification remains an exact comparison. The helper no longer emits an
unvalidated deeplink; use the normal import modal.

The adapter follows the observed Wootility 5.4.2/schema 15 sharing endpoint,
not a documented stable public API. Profiles are retrievable by their code.
Private release records preserve the JSON, SHA-256, adapter version, code and
verification state under `$XDG_STATE_HOME/wooting-profile-share` (default
`$HOME/.local/state/wooting-profile-share` on Linux). Repeating `publish` checks
and reuses the existing code for unchanged settings. `verify` checks it again;
`verify --code CODE` adopts a matching existing code. Add `--json` for structured
output or `--state-dir DIR` for a dedicated private directory (mode `0700`).

An interrupted upload is never automatically repeated. Retry `verify` when a
candidate code was saved, or recover the candidate printed on stderr using
`verify --code CODE`. If no code is recoverable, `publish --republish` explicitly
creates another publication and archives the previous record. Keep the release
records; losing them also loses local deduplication. Network failures and
read-back mismatches return an error. No build or activation publishes a profile.

If the adapter or sharing service is unavailable, preserve a backup of the
current typing profile and use it as the starting point for a work copy named
**Mac Work**. In Wootility's Remap UI, change these four positions on the main
AND Fn layers:

| Physical position | Set to in Wootility |
| --- | --- |
| Left Win | Left Alt / Option |
| Left Alt | Left Windows / Command |
| Right Alt | Right Windows / Command |
| Right Ctrl | Right Alt / Option |

Leave left Control and Fn in place. Save, reconnect and verify. Keycap labels
should match the new roles. Do not also swap Command/Option in macOS settings
or a Linux modifier remapper. Use this one work profile on both operating systems.

Typing actuation, lighting, Caps Lock and all other Fn mappings are inherited
unchanged. The native JSON is the authoritative generated reference. Wootility’s Share
action can produce a repeat-import code after applying the manual fallback.

In the repository, edit the readable `modifiers` and `workRemaps` definitions
in `hosts/nixos/desktop/local/hardware/wooting.nix` and rebuild with:

```sh
nix build --no-link --print-out-paths \
  .#nixosConfigurations.desktop.config.system.build.wootingProfiles
```

See `docs/operations/keyboard-workflow.md` in the repository for host activation,
application shortcuts, device permissions and recovery. Building this export
does not activate either host or program the keyboard.
