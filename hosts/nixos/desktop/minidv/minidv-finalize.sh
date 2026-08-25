#!@bash@
# shellcheck shell=bash
set -euo pipefail

@minidvRuntime@

usage() {
  cat <<'USAGE'
Usage: minidv-finalize --confirm-tape-ended ABSOLUTE_TAPE_DIRECTORY

Finalize one raw-DV capture that was deliberately stopped after the camcorder
reached its physical tape end. This is an explicit operator assertion: DV over
FireWire has no end-of-stream signal, so software cannot reliably distinguish
a physical tape end from a paused tape.

The command never alters DV bytes. It refuses active captures or an existing
master, moves the one retained raw-DV file and date sidecars into the normal
archive layout, then runs minidv-verify. It must not be used for a capture
stopped partway through a tape.
USAGE
}

fail() {
  printf 'minidv-finalize: %s\n' "$*" >&2
  exit 1
}

if [ "$#" -ne 2 ] || [ "$1" != --confirm-tape-ended ]; then
  usage >&2
  exit 2
fi

case "$2" in
/*) tape_directory=$2 ;;
*) fail "TAPE_DIRECTORY must be an absolute path." ;;
esac
tape_directory=$(realpath -e -- "$tape_directory")
tape_id=$(basename -- "$tape_directory")
master_directory="$tape_directory/master"
metadata_directory="$tape_directory/metadata"
capture_metadata="$metadata_directory/capture-info.txt"
final_master="$master_directory/$tape_id.dv"

[ -d "$master_directory" ] || fail "missing master directory '$master_directory'."
[ -f "$capture_metadata" ] || fail "missing capture metadata '$capture_metadata'."
if [ -e "$final_master" ]; then
  fail "the final master '$final_master' already exists; refusing to overwrite it."
fi

if pgrep -u "$(id -u)" -f "(^|/)minidv-capture( |$).*${tape_id}|dvgrab.*${tape_id}" >/dev/null; then
  fail "a MiniDV capture for '$tape_id' still appears active; stop it and confirm the output is stable first."
fi

shopt -s nullglob
captures=("$master_directory"/*.dv)
if [ "${#captures[@]}" -ne 1 ]; then
  fail "expected exactly one retained raw-DV file, found ${#captures[@]}."
fi
source_master=${captures[0]}
[ -s "$source_master" ] || fail "retained raw-DV file '$source_master' is empty."

# Confirm the file is a readable DV stream before changing names. This is a
# lightweight structural test; minidv-verify performs the full post-finalize
# validation and checksum generation.
video_codec=$(ffprobe -v error -show_streams -of json -- "$source_master" | jq -r '[.streams[]? | select(.codec_type == "video") | .codec_name] | first // empty')
audio_streams=$(ffprobe -v error -show_streams -of json -- "$source_master" | jq '[.streams[]? | select(.codec_type == "audio")] | length')
if [ "$video_codec" != dvvideo ] || [ "$audio_streams" -lt 1 ]; then
  fail "retained file is not a readable DV capture with audio; preserved it unchanged for investigation."
fi

sidecars=("$master_directory"/*.srt0 "$master_directory"/*.srt1)
if [ "${#sidecars[@]}" -gt 2 ]; then
  fail "found more than two recording-date sidecars; preserved all files for manual review."
fi

umask 077
exec 9>"$(dirname -- "$tape_directory")/.minidv-capture.lock"
if ! flock -n 9; then
  fail "another MiniDV capture currently holds the archive lock."
fi

mv -- "$source_master" "$final_master"
for sidecar in "${sidecars[@]}"; do
  [ -e "$sidecar" ] || continue
  mv -- "$sidecar" "$metadata_directory/$(basename "$sidecar")"
done

printf 'capture_state=complete-pending-verification\ncompletion_method=manual-tape-end\nmanual_end_finalized_at=%s\nmaster=%s\n' \
  "$(date --iso-8601=seconds)" "$final_master" >>"$capture_metadata"

if ! @minidvVerify@ "$tape_directory"; then
  printf 'capture_state=verification-failed\nverified_at=%s\n' "$(date --iso-8601=seconds)" >>"$capture_metadata"
  fail "capture was preserved and finalized by name, but did not pass verification; do not treat it as archived."
fi

printf 'capture_state=verified\ncompletion_method=manual-tape-end\nverified_at=%s\n' "$(date --iso-8601=seconds)" >>"$capture_metadata"
printf 'Finalized and verified %s. Create a separately stored, checksum-verified second copy before treating it as preserved.\n' "$final_master"
