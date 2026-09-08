# System font audit research

Research date: 2026-09-06. This note covers Fontconfig policy, CJK language selection, duplicate faces, and system versus Home Manager discovery. The separate Zen and EmojiTest reports document the already diagnosed emoji defects.

## Proven discrepancy: emoji selection outside Home Manager

On the active desktop, a normal user query selects the dedicated Noto Color Emoji 2.051. The same query with `XDG_CONFIG_HOME` set to an empty temporary directory selects `google-fonts`' older `share/fonts/truetype/NotoColorEmoji-Regular.ttf`. The system policy therefore still exposes the older face to contexts without this user's Home Manager configuration. This is a confirmed coverage-policy gap, even though the interactive user's previous repair is active.

Home Manager generates a configuration under the user's XDG directory that adds its profile font directories, packaged configuration fragments, and a prebuilt cache. NixOS separately builds system font directories and caches from `fonts.packages`. A rule installed only by Home Manager cannot be relied on by a service or another account. The appropriate fix is to apply the same validated emoji selection policy through an active NixOS module. Sources: [Home Manager fontconfig module](https://github.com/nix-community/home-manager/blob/master/modules/misc/fontconfig.nix), [NixOS fontconfig module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/fonts/fontconfig.nix).

The empty-XDG probe still discovers system Noto Sans CJK 2.004, Noto Serif CJK 2.003, and Noto Sans Mono CJK. There is no evidence of a system-level CJK package omission in this configuration.

## CJK face selection needs a rendering check

Both generated default-font configurations use `binding="same"` and put SC before TC, HK, JP, and KR. On this desktop, `fc-match 'sans-serif:lang=ja:charset=9aa8'` and the corresponding Korean query both select `Noto Sans CJK SC`.

Fontconfig gives strong family values priority over language and weak family values lower priority than language. A `same` binding inherits the matched value's binding. This explains why a strongly requested generic family can retain the configured regional order. Source: [Fontconfig matching and configuration manual](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html).

That face name alone does **not** prove that Japanese or Korean text is drawn incorrectly. Noto CJK's full regional faces contain glyphs for the other regions, accessible through language tagging and OpenType `locl`. Upstream identifies modern browsers as supporting this mechanism. Also, the installed SC face's Fontconfig language set includes Japanese, Korean, and multiple Chinese locales, so merely weakening the fallback binding is not guaranteed to select the regional face. Source: [Noto Sans CJK deployment guide](https://github.com/notofonts/noto-cjk/blob/main/Sans/README.md).

Before changing policy, compare tagged Japanese, Korean, simplified Chinese, Taiwan, and Hong Kong samples against the corresponding explicit regional faces. Include shared Han characters such as U+9AA8 骨. If a native application ignores shaping language, a conditional regional fallback can help, but it should preserve Inter/Literata/Monaspace for Latin text and respect explicit font choices. Untagged shared ideographs do not contain enough information to infer the author's preferred regional form.

## Duplicate families are candidates, not automatic defects

Fontconfig compares many properties before font version: character coverage, family, language, spacing, size, style, weight, and others. Installing a newer face does not by itself establish which face will win a given request. Its implementation also treats variable faces and named instances separately. This means auditing duplicate *family names* without considering face index, style, variable instances, file identity, and actual selection would produce false positives. Source: [Fontconfig match implementation](https://github.com/fontconfig/fontconfig/blob/main/src/fcmatch.c).

Use the selected file and face index when checking coverage. Treat a duplicate as a defect when it shadows intended coverage, creates a build collision, changes the chosen metrics unexpectedly, or supplies a faulty rule. The known Google Noto emoji copy meets the coverage criterion; multiple weights and separate regional faces do not.

## Cache and rendering policy

Home Manager creates its profile cache at build time, and NixOS builds caches for its configured font packages. Rebuilding all user caches should not be the default repair for an immutable store configuration. First verify which configuration and directories are loaded, whether cache reads emit errors, and whether the selected files exist. A fresh process is useful when comparing a changed policy because applications may retain their own font lists. Sources: [Home Manager cache construction](https://github.com/nix-community/home-manager/blob/master/modules/misc/fontconfig.nix), [NixOS cache construction](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/fonts/fontconfig.nix).

Fontconfig's non-Latin defaults already supply fallback families for many scripts. A selected family that differs from the preferred Latin font can be ordinary fallback rather than a fault. Verify painted glyphs and shaping for representative scripts before replacing those rules. Source: [Fontconfig non-Latin fallback configuration](https://github.com/fontconfig/fontconfig/blob/main/conf.d/65-nonlatin.conf).

No configuration files were changed by this research subtask. These are initial findings, not a claim that every application, language, or font face has been visually verified.

## Completed audit and fixes

The follow-up checks on desktop found two configuration gaps and fixed both:

- The emoji rejection rule was only active in Home Manager. The XML now lives in `modules/shared/font-selection.conf`. A shared NixOS module imports it from both the active Stylix module and the font collection modules, so other users and system services receive the same selection. With an empty XDG configuration, the old system policy passed 3,805 of 3,953 Unicode 17 RGI entries. The built policy passes all 3,953 using Noto Color Emoji 2.051.
- Zen's existing profile had `gfx.font_rendering.fontconfig.max_generic_substitutions = 127`, but the repository did not preserve that setting. An isolated profile using the default limit of three displayed missing-glyph boxes for Telugu, Khmer, and Myanmar despite having suitable fonts installed. Setting only the limit to 127 fixed the samples. The shared Linux Gecko profile now declares 127 for both Zen and Firefox. Mozilla documents this preference as the bound on Fontconfig generic-family substitutions; a low limit can truncate longer substitution lists. Sources: [original Mozilla change](https://bugzilla.mozilla.org/show_bug.cgi?id=1224965), [current coverage report](https://bugzilla.mozilla.org/show_bug.cgi?id=1970417).

Repeated package entries for Material Design Icons, Source Sans, and TeX Gyre were also removed from the shared font list. This is housekeeping, not a rendering fix.

### Validation

- Fontconfig enumerated 22,254 faces through 9,300 visible paths, resolving to 5,198 distinct files. Every visible path existed. FontTools read the initial face's cmap, head, maxp, and name tables in all 5,145 OpenType containers without exceptions. This is a structural check, not exhaustive validation of every glyph, table, or collection member. Some third-party files have old timestamp metadata warnings; these did not prevent parsing or rendering.
- The selected Arial, Times New Roman, Verdana, Tahoma, and Segoe UI fonts came from the Windows 11 package. Inter and Roboto selected their dedicated packages. Other overlapping families include legitimate variable/static and OpenType/TrueType variants, so they were not removed without evidence of a defect.
- The 16 language samples passed HarfBuzz missing-glyph checks. Visual inspection was also necessary: the default browser fallback limit still produced three rows of boxes. With the declared limit, all 16 browser rows render text, and the math/symbol row renders. The sample browser console recorded no downloadable-font or sanitizer diagnostics.
- All 15 CJK browser comparisons, five languages across sans-serif, serif, and monospace, matched the corresponding explicit regional face pixel-for-pixel after cropping to the painted bounds. Generic and explicit fonts can have different ascents, so comparing uncropped boxes gave false failures. The CJK policy was left unchanged.
- The numeric regression covers 160 digits across eight font families with normal and tabular styles. The multilingual regression compares actual browser pixels for Telugu, Khmer, and Myanmar against their installed reference fonts, including Padauk for Myanmar. It is designed for this desktop's installed font collection.
- The user emoji test still passes all 3,953 Unicode 17 RGI entries. The system policy was tested separately with user configuration disabled and the candidate system's Fontconfig files.
- The recent two-hour journal check found allowed AppArmor font/cache reads and harmless Home Manager messages about identical files. It found no actionable Fontconfig parsing/cache errors or NVIDIA Xid/GPU reset messages in that window. Binary coredump payloads are not interpreted as font errors. Earlier EmojiTest sanitizer failures remain explained in the separate report and are not resolved by bypassing validation.

Browser evidence: [default limit](assets/system-font-audit/multilingual-default-limit.png), [declared limit](assets/system-font-audit/multilingual-fixed.png). Machine-readable evidence: [inventory](assets/system-font-audit/inventory.json), [CJK comparisons](assets/system-font-audit/cjk-results.json).

Run the browser regression with Python containing selenium and Pillow, plus geckodriver:

```sh
python tests/browsers/check_font_rendering.py --suite multilingual --generic-substitutions 3 --output /tmp/font-before --headed
python tests/browsers/check_font_rendering.py --suite multilingual --output /tmp/font-after --headed
python tests/browsers/check_font_rendering.py --output /tmp/font-digits --headed
```

The first command is the negative control and should fail on this font stack. The other two should pass. Use `--browser` and `--geckodriver` if the executables are not on PATH. The default substitution limit is the declared profile value, 127.

The full desktop system was built on desktop with `nix build path:.#nixosConfigurations.desktop.config.system.build.toplevel`. Activation requires authenticated sudo. This audit verifies the cases above; it cannot certify every glyph in every installed font or every website's downloadable font.

Final built system: `/nix/store/pym7azqil3whqdjmsxd1j6i1ixasm116-nixos-system-desktop-26.11.20260826.9fbb54b`. The active system at final verification was `/nix/store/zaw2s7kckiayl7n9kd51mxpvdv2xgam7-nixos-system-desktop-26.11.20260826.9fbb54b` and still selected the older emoji font without Home Manager. The new system policy and declared profile preference remain pending activation. The interactive Zen profile already retains its working value of 127. Nix formatting, Ruff, Python type checks, and `git diff --check` passed.
