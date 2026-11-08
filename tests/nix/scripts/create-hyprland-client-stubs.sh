# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/bin"
touch "$out/bin/hyprctl" "$out/bin/Hyprland"
chmod +x "$out/bin/hyprctl" "$out/bin/Hyprland"
