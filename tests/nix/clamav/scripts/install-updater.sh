# shellcheck shell=bash
# Nix's builder supplies the output directory.
# shellcheck disable=SC2154
ln -sfn @freshclam@ "$out/bin/freshclam"
