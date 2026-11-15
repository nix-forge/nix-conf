# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
runHook preInstall
install -Dm755 subsurface-rounding-client "$out/bin/subsurface-rounding-client"
runHook postInstall
