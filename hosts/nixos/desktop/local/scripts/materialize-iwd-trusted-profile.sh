#!@bash@
# shellcheck shell=bash
set -euo pipefail

@install@ -d -m 0700 /var/lib/iwd
templatePath=@templatePath@
ssid="$(@sed@ -n '1{s/^SSID=//;p;q;}' "$templatePath")"
case "$ssid" in
"" | */* | .*)
  echo "sealed IWD SSID is not a safe profile filename" >&2
  exit 1
  ;;
esac
profilePath="/var/lib/iwd/$ssid.psk"
candidate="$(@mktemp@ "/var/lib/iwd/.iwd-profile.tmp.XXXXXX")"
trap '@rm@ -f "$candidate"' EXIT
@tail@ -n +2 "$templatePath" >"$candidate"
@chmod@ 0600 "$candidate"
if ! @cmp@ -s "$candidate" "$profilePath"; then @mv@ -f "$candidate" "$profilePath"; fi
