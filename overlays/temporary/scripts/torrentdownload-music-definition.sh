# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @source@ torrentdownload.yml
chmod u+w torrentdownload.yml
patch --fuzz=0 -p1 <@patches_prowlarr_torrentdownload_patch@
python3 @tests_prowlarr_torrentdownload_py@ torrentdownload.yml
cp torrentdownload.yml "$out"
