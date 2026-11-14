# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
run @lib_getExe_pkgs_coreutils_mkdir@ -p @lib_escapeShellArg_extensionDirectory@
@bootstrapExtensions@
