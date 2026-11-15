# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python @testSource@/tests/browsers/check_apple_emoji.py --font @personal_apple_color_emoji@/share/fonts/truetype/apple-color-emoji/font.ttf --emoji-data @emojiData@ --browser "$browser" --output "$output/apple"
