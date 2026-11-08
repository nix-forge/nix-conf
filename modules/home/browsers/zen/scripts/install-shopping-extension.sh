# shellcheck shell=bash
if [[ ! -e @lib_escapeShellArg_destination@ ]]; then
  run @lib_getExe_pkgs_coreutils_install@ -m 0644 \
    @lib_escapeShellArg_extension_package@ \
    @lib_escapeShellArg_destination@
fi
