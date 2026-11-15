# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @config_checks_font_native@/*.png "$output/"
python @testSource@/tests/fonts/check_emoji_coverage.py --emoji-data @emojiData@ --font @personal_apple_color_emoji@/share/fonts/truetype/apple-color-emoji/font.ttf
