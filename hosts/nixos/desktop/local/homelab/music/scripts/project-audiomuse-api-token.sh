# shellcheck shell=bash
set -eu
target=@lib_escapeShellArg_bootstrapAudioMuseCredential@
partial="$target.partial"
trap '@pkgs_coreutils@/bin/rm -f "$partial"' EXIT
builtin printf '%s' "$API_TOKEN" >"$partial"
@pkgs_coreutils@/bin/chmod 0400 "$partial"
@pkgs_coreutils@/bin/mv "$partial" "$target"
trap - EXIT
