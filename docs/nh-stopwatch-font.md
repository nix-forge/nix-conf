# Small nh stopwatch in Ghostty

Investigated on desktop on 2026-09-06 with nh 4.4.2, nix-output-monitor 2.2.0, and Ghostty 1.3.1.

The icon is the correct character, U+23F1 STOPWATCH. nh uses nix-output-monitor for build output. Its timer uses the bare stopwatch character, without a text or emoji variation selector. The installed nom binary contains `E2 8F B1 00`, confirming the bare UTF-8 string. The [upstream output implementation](https://github.com/maralorn/nix-output-monitor/blob/main/nix-output-monitor/lib/NOM/Print.hs) names this value `clock` and uses it before the elapsed time.

## Cause and correction

The generated Ghostty configuration listed both MonaspiceNe Nerd Font and Noto Color Emoji as explicit font families. This made the bare stopwatch select the color face. It was scaled down to fit its single terminal cell, producing the tiny icon in the user's screenshot.

Removing the explicit color family lets Ghostty distinguish text and emoji presentation during fallback. Its font diagnostics then select Noto Emoji for the bare stopwatch and Noto Color Emoji for emoji presentation. Ghostty documents that explicitly listing an emoji-containing family overrides its normal emoji handling. Source: [Ghostty font-family reference](https://ghostty.org/docs/config/reference#font-family).

The Linux settings in `modules/home/terminals/ghostty/default.nix` now override Stylix's generated font-family list with the configured monospace family alone. The font packages and system/browser fallback rules are unchanged. The macOS branch was not changed because this reproduction was on Linux.

A trial mapping U+23F1 directly to Noto Sans Symbols 2 improved the bare glyph but broke the explicit emoji variant. That mapping was rejected and is not installed.

## Verification and application

The reproduction prints bare, text-selector, emoji-selector, and bold stopwatches, plus digits and color emoji, in isolated Ghostty windows. At the same 18-point test size, the bare stopwatch's painted bounds increased from 15 by 19 pixels to 31 by 36 pixels. The final capture used the live generated config without a command-line font-family override. Digits, smiley, red heart, and keycap emoji remained visible; the explicitly requested stopwatch emoji remained colored.

Evidence: [before](assets/nh-stopwatch/before.png), [after](assets/nh-stopwatch/after.png), [pixel measurements](assets/nh-stopwatch/measurements.json).

The Home Manager Ghostty config derivation built successfully. `ghostty +validate-config`, Nix formatting, and `git diff --check` passed. This change only requires the generated user configuration, so no full NixOS system build was needed.

The live `~/.config/ghostty/config` symlink now points to the generated `/nix/store/v2yibcgzi72c326bsfwqmhrnb1qx8dmy-ghostty-config`. The prior link was preserved at `/tmp/nh-icon-audit/original-config`. The Nix source retains the change for future Home Manager activations. Existing Ghostty windows can reload with Ctrl+Shift+comma, then open a new tab or window if necessary. No terminal sessions were restarted; only the isolated diagnostic windows were closed.

Quick checks for the active configuration:

```sh
ghostty +show-face --cp=0x23F1
ghostty +show-face --cp=0x23F1 --style=bold
ghostty +show-face --cp=0x23F1 --presentation=emoji
```

The first two select Noto Emoji and the third selects Noto Color Emoji on this desktop. `show-face` does not account for complete grapheme clusters, so the actual terminal screenshots also checked the variation-selector cases.
