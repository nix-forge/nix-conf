# VS Code nh stopwatch

Investigated on the Linux desktop with VS Code 1.133.0, nh 4.4.2, and nix-output-monitor 2.2.0 on 2026-09-06.

## Reproduction and cause

The symbol is U+23F1 STOPWATCH, emitted without a variation selector by nix-output-monitor. The same bare, bold character was printed in an isolated VS Code integrated terminal using the live font settings. Its painted bounds were 13 by 27 pixels, reproducing the narrow oval in the reported screenshot. See the [earlier nh investigation](nh-stopwatch-font.md) for the binary and source identification.

VS Code enables `terminal.integrated.rescaleOverlappingGlyphs` by default. It squeezes glyphs that would extend beyond their assigned terminal cells. Chromium selects a wide color stopwatch through font fallback, but the bare character occupies one cell. Disabling rescaling changed the measured bounds to 24 by 27 pixels. This identified horizontal rescaling as the immediate cause. [VS Code terminal appearance](https://code.visualstudio.com/docs/terminal/appearance#_rescaling-ambiguous-width-glyphs), [VS Code configuration source](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/terminal/common/terminalConfiguration.ts).

## Fix

The VS Code terminal now uses this family list:

```text
'MonaspiceNe Nerd Font', 'Iosevka Charon Mono'
```

The first family still follows the configured Stylix monospace family. Iosevka Charon Mono is already installed by the shared Google Fonts package on Linux and Darwin. It supplies a text stopwatch designed for a terminal cell. No additional package or font-file modification is needed.

The fallback changed the measured bare bold stopwatch to 16 by 19 pixels. The explicit emoji selector still produces a colored stopwatch. Glyph rescaling and GPU acceleration remain enabled. A global rescaling disable was rejected because it also allows other wide symbols to overlap adjacent text. Noto Sans Symbols 2 and Segoe UI Symbol fallback trials did not resolve the measured distortion.

## Verification

The diagnostic fixture contains bare bold and normal stopwatches, both variation selectors, color emoji, digits, letters, box drawing, and Nerd Font symbols. In the same running diagnostic window, the color-emoji, digit/letter, and box/Nerd-symbol rows were pixel-identical before and after changing the fallback. This checks preservation of their existing rendering, not complete support for every emoji grapheme sequence in VS Code.

Screenshots: [before](assets/vscode-stopwatch/before.png), [after](assets/vscode-stopwatch/after.png).

The permanent check launches an isolated VS Code profile, prints the actual stopwatch through its integrated terminal, captures the rendered pixels through Chromium's debugging protocol, and rejects a narrow aspect ratio. It closes only its own diagnostic application. It requires a graphical session, Python with Pillow and websocket-client, and the `code` command:

```sh
python tests/terminals/check_vscode_stopwatch.py \
  --settings ~/.config/Code/User/settings.json \
  --output /tmp/vscode-stopwatch-check
```

The permanent check failed with the original settings at 13 by 27 pixels and passed with the applied settings at 16 by 19 pixels. [Recorded results](assets/vscode-stopwatch/results.json).

The Linux Home Manager settings derivation built successfully. The Darwin settings evaluated with the same fallback and default rescaling enabled. Native Darwin rendering was not tested because the Mac was unavailable.

The live Linux settings symlink was updated to the built settings file. A comparison before applying it confirmed that `terminal.integrated.fontFamily` was the only changed setting. The previous symlink target is recorded in `/tmp/vscode-stopwatch-audit/original-settings-link`. VS Code watches this settings file and updates its terminal font without restarting terminal processes.
