# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/share/systemd"
ln -s @dropIn@ "$out/share/systemd/workspace-ingress.conf"
