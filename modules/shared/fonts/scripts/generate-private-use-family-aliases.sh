# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
@privateUseFamilyAliases@/bin/fontconfig-private-use-family-aliases "$out/aliases.conf"
