# shellcheck shell=bash
# Nix supplies the configured package directory and builder output.
# shellcheck disable=SC2154
mkdir -p "$out"
for name in audiomuseai listenbrainz-daily-playlist nd-lyrics; do
  archive="$pluginFolder/$name.ndp"
  test -f "$archive"
  unzip -t "$archive" >"$out/$name-archive.txt"
  unzip -p "$archive" manifest.json >"$out/$name.json"
  jq -e '.name != null and .version != null' "$out/$name.json"
  unzip -p "$archive" plugin.wasm >plugin.wasm
  od -An -tx1 -N4 plugin.wasm | grep -q '00 61 73 6d'
done
# The custom AudioMuse variant must retain its loopback-only permission.
jq -e '.permissions.http.requiredHosts == ["127.0.0.1"]' "$out/audiomuseai.json"
