# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
for rule in @pkgs_fontconfig_out@/etc/fonts/conf.d/*.conf; do
  name=$(basename "$rule")
  case "$name" in 50-user.conf | 51-local.conf) continue ;; esac
  ln -s "$(readlink -f "$rule")" "$out/$name"
done
