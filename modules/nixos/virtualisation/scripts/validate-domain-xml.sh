# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @source@ "$out"
@getExe_config_virtualisation_libvirtd_package_virt_xml_valid@ "$out" domain
