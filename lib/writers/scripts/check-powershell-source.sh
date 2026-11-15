# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache" XDG_CONFIG_HOME="$TMPDIR/config"
export DOTNET_CLI_HOME="$TMPDIR/dotnet" POWERSHELL_TELEMETRY_OPTOUT=1
mkdir -p "$HOME"
@lib_getExe_pkgs_powershell@ -NoLogo -NoProfile -NonInteractive \
  -File @check_powershell_ps1@ -Path "$target" \
  -Analyzer @analyzer_modulePath@/PSScriptAnalyzer.psd1 -Settings @settings@
