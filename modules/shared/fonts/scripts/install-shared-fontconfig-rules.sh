# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
install -d "$out/etc/fonts/conf.d"
ln -s @rendered_cssGenericAlias@ "$out/etc/fonts/conf.d/51-shared-css-generic-alias.conf"
ln -s @rendered_privateUseFallback@ "$out/etc/fonts/conf.d/51-shared-private-use-fallback.conf"
