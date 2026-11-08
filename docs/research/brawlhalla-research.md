# Brawlhalla keyboard and desktop settings

Reviewed 2026-10-07. The desktop configuration exports its chosen settings to
`/etc/brawlhalla/settings.json` through
[the local module](../../hosts/nixos/desktop/local/gaming/brawlhalla.nix).
The game settings were applied and checked separately. Nix does not overwrite
Steam account data or binary game saves during activation.

## Controls

| Key | Action |
| --- | --- |
| A / D | Move left / right |
| S | Aim down and drop through platforms |
| W | Aim up, without jumping |
| Space | Jump |
| Shift | Dodge / dash |
| J | Light attack |
| K | Heavy attack / recovery |
| L | Throw / pick up weapon |
| Tab | Scores |
| 1–8 | Taunts |

Enable **Prioritize Neutral Over Side** and disable **Pickup With Quick Attack**.
Separating jump from aim up permits upward aiming without spending a jump.
A dedicated pickup key prevents a light attack from unexpectedly picking up a
weapon. Neutral priority makes up plus sideways input select a neutral attack.
The exact J/K/L arrangement is an ergonomic choice, not a demonstrated universal
optimum. Practice is still needed to learn the new keys.

A [firsthand keyboard discussion](https://steamcommunity.com/app/291550/discussions/0/1638662230378197628/)
describes separate jump and aim controls.
[Phazon's settings guide](https://www.youtube.com/watch?v=41krQVAE-8g)
recommends disabling quick-attack pickup. Neither establishes one best layout
for every player.

Use the Wooting **FPS** profile, selected with **Fn+2**. Its WASD rapid trigger
can release movement promptly, with direct keyboard input and no automated
combos or direction arbitration. See [the keyboard guide](../operations/wooting-keyboard.md)
for its actual actuation values. If accidental movement is a problem, the
**Casual** profile, **Fn+4**, is a less sensitive alternative with identical keys.

## Display and visibility

Use fullscreen and `-setfps 240` on a 240 Hz display. The
[official 9.00 patch notes](https://www.brawlhalla.com/news/9th-anniversary-patch-900)
say to match `-setfps` to the monitor refresh rate. They also say that framefix
is the default, `-unlockfps` is deprecated, and `-triplebuffer` is experimental
and may hurt performance. The selected launch options contain only
`-setfps 240`; reassess this value if the display changes.

Default camera, medium background blur, HUD-only names, and team icons provide
a readable starting point. The
[official background-options release](https://www.brawlhalla.com/news/new-background-options-balance-and-magyar-skin-patch-6-10)
describes the built-in blur settings and their reduction of background movement.
These visibility choices are preferences, not measured latency improvements.
Waiting-room Training Mode permits practice while queued. Effects are 70% and
music is muted. Damage numbers stay off, and the stock timer appears during the
last minute. Cosmetics, language, account state, and replay retention are
independent of this preset.

Keep the existing network acceleration behavior. The
[official Network Next introduction](https://www.brawlhalla.com/news/battle-pass-season-7-valhallaquest-patch-7-03)
explains its routing purpose; it does not justify disabling it on every system.
Choose a server region using actual connection latency. A desktop's timezone
alone does not establish the fastest server.

## Persistence and recovery

The game stores settings in AMF3 `.sol` files under the Proton prefix:

```text
steamapps/compatdata/291550/pfx/drive_c/users/steamuser/AppData/Roaming/
  BrawlhallaAir/Local Store/#SharedObjects/
```

`bhKeybinds.sol` owns the keyboard fields and `sbSavedGameData.sol` owns the
preferences. Steam stores the app's `LaunchOptions` in the active account's
`config/localconfig.vdf`, under app ID `291550`.

Close the game and Steam before editing these files. Back them up privately.
Apply only the fields in the exported JSON, preserving unknown fields and
account state. These saves require an AMF3-aware reader and writer, such as
Py3AMF. A JSON file cannot simply replace them. Verify an encode/decode
roundtrip before atomic replacement, then inspect the controls and preferences
inside the restarted game. Steam Properties can also set the launch options,
and the game menus can apply all preferences without a binary editor.

This setup was applied using game menus with a targeted AMF3 patch for Shift,
which synthetic modifier input failed to save. The resulting files passed
roundtrip checks, with unrelated fields preserved. Private backups and captures
remain outside this repository. A future save format change requires repeating
the in-game checks before reapplying numeric fields.
