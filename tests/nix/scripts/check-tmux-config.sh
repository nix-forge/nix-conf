# shellcheck shell=bash
# Nix supplies isolated build paths and expected values.
# shellcheck disable=SC2154
export HOME="$TMPDIR/home"
mkdir -p "$HOME"
python3 @checkScript@ "$configuration" "$expectedPath" @holdCommand@
touch "$out"
