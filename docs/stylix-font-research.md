# Fonts for the Stylix desktop

## Recommendation

Keep the existing Stylix quartet:

| Role | Font | Why it belongs there |
| --- | --- | --- |
| UI and general sans text | Inter | Designed for computer screens, with a tall x-height and broad weight range. It is the right default for GTK, Qt, browsers, Electron applications, launchers, and panels. |
| Reading serif | Literata | A screen serif made for sustained reading. Use it for documents, ebook readers, web pages that request a serif family, and office applications. |
| Code, terminals, and icon-bearing bars | MonaspiceNe Nerd Font | Monaspace Neon is made for code and supports Monaspace's ligatures and character variants. The Nerd Font build adds the terminal and status-bar icons that this desktop uses. |
| Emoji | Noto Color Emoji | A Unicode color emoji font with current Linux and Chromium support. |

This quartet is already declared in [modules/shared/stylix.nix](/Users/ianmh/Developer/personal/nix-conf/modules/shared/stylix.nix), which the desktop Home Manager profile selects. It is a better all-purpose choice than changing every role to one family. Inter is not a CJK font and Monaspace is not a general UI font. That is expected. Fontconfig should select the Latin primary face first, then a purpose-built fallback for scripts it does not cover.

For a Linux desktop that reads CJK text, use Noto Sans CJK after Inter, Noto Serif CJK after Literata, and Noto Sans Mono CJK after MonaspiceNe. The repository has this exact NixOS fallback order in [modules/nixos/stylix-components/fonts.nix](/Users/ianmh/Developer/personal/nix-conf/modules/nixos/stylix-components/fonts.nix). The current desktop host does not select that module, so it is a ready-made option rather than a verified system-wide setting. The Noto project specifically recommends pairing a preferred Latin font with a Noto fallback for other scripts. It supplies regional CJK variants for Simplified Chinese, Traditional Chinese, Hong Kong, Japanese, and Korean.

Keep `Noto Color Emoji` as the emoji family. Do not put it into the sans, serif, or monospace lists. NixOS treats emoji as its own Fontconfig alias, and Fontconfig gives color emoji special matching treatment.

## What Stylix and NixOS actually control

Stylix has four font roles: `serif`, `sansSerif`, `monospace`, and `emoji`. Each has a Nix package and a Fontconfig family name. Enabling Stylix installs those four packages and its Fontconfig target prepends the configured family names to NixOS's default family lists. `autoEnable` covers most available targets, but it cannot force every program, Flatpak, browser site, or terminal application to use them.

NixOS renders `fonts.fontconfig.defaultFonts` as ordered Fontconfig `<prefer>` lists. These lists are fallback preferences, not an absolute override. The first family should be the desired Latin face. Add only the script-specific Noto families that are needed after it. This repository follows that pattern in its NixOS font module.

The virtual console is separate from Stylix's GUI font roles. It uses a console font through the NixOS `console` options. The current [boot console module](/Users/ianmh/Developer/personal/nix-conf/modules/nixos/boot/console.nix) deliberately leaves that as a host-local decision, which is reasonable. Do not try to use a proportional UI typeface there. If console customization becomes desirable, choose a bitmap or console-optimized monospace face separately and test it at the boot prompt.

## Practical checks after a rebuild

Use the exact names reported by Fontconfig, not a package attribute or a filename. Nerd Fonts have changed their family naming in past releases, so this is worth checking whenever the package changes.

```sh
fc-match sans-serif
fc-match serif
fc-match monospace
fc-match emoji
fc-match -s monospace | sed -n '1,12p'
fc-query /path/to/a/font-file | rg '^\s+family:'
```

The first four commands should resolve to Inter, Literata, MonaspiceNe Nerd Font, and Noto Color Emoji for the desktop user. If the NixOS CJK fallback module is selected, the expanded monospace result should show the CJK fallback families after the primary face. For a program that has its own font setting, such as a terminal, editor, or status bar, use the same Fontconfig family name and restart the program after changing fonts.

## Licensing and upstream status

All four primary choices are freely redistributable under the SIL Open Font License 1.1. The Nerd Font package carries Monaspace's OFL terms and adds icon glyphs. Noto CJK also uses OFL. The Noto Emoji repository distinguishes its font files, which use OFL, from tools and most image resources, which use Apache-2.0.

## Sources

- [Stylix NixOS font options](https://nix-community.github.io/stylix/options/platforms/nixos.html)
- [Stylix font role implementation at this flake's locked revision](https://github.com/nix-community/stylix/blob/a9e5a76a1b75b137f266e4f445e1eaba82e9783e/stylix/fonts.nix)
- [Stylix NixOS Fontconfig target at this flake's locked revision](https://github.com/nix-community/stylix/blob/a9e5a76a1b75b137f266e4f445e1eaba82e9783e/modules/fontconfig/fontconfig.nix)
- [Nixpkgs Fontconfig module at this flake's locked revision](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/config/fonts/fontconfig.nix)
- [NixOS Fonts guide](https://wiki.nixos.org/wiki/Fonts)
- [Inter upstream repository and OFL notice](https://github.com/rsms/inter)
- [Literata upstream repository and OFL notice](https://github.com/googlefonts/literata)
- [Monaspace upstream repository and OFL notice](https://github.com/githubnext/monaspace)
- [Nerd Fonts supported-font metadata](https://github.com/ryanoasis/nerd-fonts)
- [Noto guidance for global-script fallbacks](https://notofonts.github.io/noto-docs/website/use/)
- [Noto CJK upstream repository](https://github.com/notofonts/noto-cjk)
- [Noto Emoji upstream repository and license](https://github.com/googlefonts/noto-emoji)
