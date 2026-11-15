# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export XDG_CACHE_HOME="$TMPDIR/font-cache"
mkdir -p "$out"
python @testSource@/tests/fonts/check_selection.py --providers @providers@ --output "$out/selection.json"
python @testSource@/tests/fonts/check_emoji_coverage.py --emoji-data @emojiData@
