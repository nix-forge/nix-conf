# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python @source@/site/build.py --source @source@ --output "$out" \
  --catalog @config_packages_feature_catalog@ \
  --options @config_packages_feature_options@/share/doc/nixos/options.json
test -s "$out/index.html"
test -s "$out/search/search_index.json"
