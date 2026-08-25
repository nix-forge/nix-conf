#!@bash@
# shellcheck shell=bash
set -euo pipefail

@minidvRuntime@

usage() {
  cat <<'USAGE'
Usage: minidv-verify ABSOLUTE_TAPE_DIRECTORY

Verify one raw-DV MiniDV master created by minidv-capture. The command never
changes the .dv master. It creates a checksum only when one is not present and
writes a timestamped ffprobe/verification log beside the capture.
USAGE
}

fail() {
  printf 'minidv-verify: %s\n' "$*" >&2
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

case "$1" in
/*) tape_directory=$1 ;;
*) fail "TAPE_DIRECTORY must be an absolute path." ;;
esac
tape_directory=$(realpath -e -- "$tape_directory")
master_directory="$tape_directory/master"
logs_directory="$tape_directory/logs"
metadata_directory="$tape_directory/metadata"
capture_log="$logs_directory/capture.log"

[ -d "$master_directory" ] || fail "missing master directory '$master_directory'."
[ -d "$logs_directory" ] || fail "missing logs directory '$logs_directory'."
[ -d "$metadata_directory" ] || fail "missing metadata directory '$metadata_directory'."

shopt -s nullglob
masters=("$master_directory"/*.dv)
if [ "${#masters[@]}" -ne 1 ]; then
  fail "expected exactly one raw .dv master in '$master_directory', found ${#masters[@]}."
fi
master=${masters[0]}
[ -s "$master" ] || fail "master '$master' is empty."
master_filename=$(basename "$master")

stamp=$(date -u +%Y%m%dT%H%M%SZ)
verification_log="$logs_directory/verify-$stamp.log"
ffprobe_json="$logs_directory/ffprobe-$stamp.json"
ffprobe_text="$logs_directory/ffprobe-$stamp.txt"
exec > >(tee "$verification_log") 2>&1

printf 'MiniDV verification: %s\n' "$master"
printf 'File size: %s bytes\n' "$(stat -c %s -- "$master")"

ffprobe -v error -show_format -show_streams -of json -- "$master" >"$ffprobe_json"
ffprobe -v error \
  -show_entries 'format=format_name,duration,size:stream=index,codec_type,codec_name,width,height,field_order,avg_frame_rate,r_frame_rate,sample_aspect_ratio,display_aspect_ratio,nb_frames,sample_rate,channels' \
  -of default=noprint_wrappers=0 -- "$master" >"$ffprobe_text"

video_codec=$(jq -r '[.streams[]? | select(.codec_type == "video") | .codec_name] | first // empty' "$ffprobe_json")
audio_streams=$(jq '[.streams[]? | select(.codec_type == "audio")] | length' "$ffprobe_json")
duration=$(jq -r '.format.duration // "unknown"' "$ffprobe_json")
width=$(jq -r '[.streams[]? | select(.codec_type == "video") | .width] | first // "unknown"' "$ffprobe_json")
height=$(jq -r '[.streams[]? | select(.codec_type == "video") | .height] | first // "unknown"' "$ffprobe_json")
frame_rate=$(jq -r '[.streams[]? | select(.codec_type == "video") | .avg_frame_rate] | first // "unknown"' "$ffprobe_json")
field_order=$(jq -r '[.streams[]? | select(.codec_type == "video") | .field_order] | first // "unknown"' "$ffprobe_json")
sample_aspect_ratio=$(jq -r '[.streams[]? | select(.codec_type == "video") | .sample_aspect_ratio] | first // "unknown"' "$ffprobe_json")
display_aspect_ratio=$(jq -r '[.streams[]? | select(.codec_type == "video") | .display_aspect_ratio] | first // "unknown"' "$ffprobe_json")
frame_count=$(jq -r '[.streams[]? | select(.codec_type == "video") | .nb_frames] | first // "not indexed"' "$ffprobe_json")

verification_ok=1
if [ "$video_codec" != dvvideo ]; then
  printf 'ERROR: expected DV video (dvvideo); ffprobe reported %s.\n' "${video_codec:-no-video-stream}"
  verification_ok=0
fi
if [ "$audio_streams" -lt 1 ]; then
  printf '%s\n' 'ERROR: no audio stream was found. This is unexpected for a normal MiniDV capture.'
  verification_ok=0
fi

printf 'Video codec: %s\n' "${video_codec:-none}"
printf 'Audio streams: %s\n' "$audio_streams"
printf 'Duration: %s seconds\n' "$duration"
printf 'Video: %sx%s, rate %s, field order %s, SAR %s, DAR %s\n' \
  "$width" "$height" "$frame_rate" "$field_order" "$sample_aspect_ratio" "$display_aspect_ratio"
printf 'Indexed frame count: %s\n' "$frame_count"

checksum="$master.sha256"
if [ -e "$checksum" ]; then
  if (cd "$master_directory" && sha256sum --check --status -- "$(basename "$checksum")"); then
    printf 'SHA-256: verified existing manifest %s\n' "$checksum"
  else
    printf 'ERROR: SHA-256 manifest does not match the raw master.\n'
    verification_ok=0
  fi
else
  # Keep the filename relative to master/ so this manifest verifies after the
  # complete tape directory is copied to another disk or the Mac.
  (cd "$master_directory" && sha256sum -- "$master_filename") >"$checksum"
  printf 'SHA-256: generated %s\n' "$checksum"
fi

if [ ! -f "$capture_log" ]; then
  printf 'ERROR: capture log is missing; capture integrity cannot be assessed fully.\n'
  verification_ok=0
else
  printf '%s\n' 'Capture log findings:'
  # Treat standalone fatal/error/failed words as serious.  Do not match the
  # hyphenated phrase "serious-error" in this verifier's own informational
  # output, which older captures may have appended to capture.log.
  if grep -E -i 'warning: [1-9][0-9]* (dropped|damaged) frames|(^|[^[:alnum:]_-])(fatal|error|failed)($|[^[:alnum:]_-])' "$capture_log"; then
    printf '%s\n' 'ERROR: capture log contains dropped/damaged frames or a serious error.'
    verification_ok=0
  else
    printf '%s\n' 'No dropped/damaged-frame or serious-error indication found in capture log.'
  fi
fi

if [ -f "$tape_directory/metadata/capture-info.txt" ]; then
  capture_state=$(awk -F= '$1 == "capture_state" { state = $2 } END { print state }' "$tape_directory/metadata/capture-info.txt")
  case "$capture_state" in
  verified | complete-pending-verification)
    ;;
  *)
    printf 'WARNING: capture metadata records an incomplete or failed state: %s\n' "${capture_state:-missing}"
    verification_ok=0
    ;;
  esac
fi

printf '%s\n' 'Manual inspection is still required: play samples from the beginning, middle, and end before declaring preservation complete.'
printf '%s\n' 'A tape is not safely preserved until this raw master has at least one independently stored, checksum-verified second copy.'

if [ "$verification_ok" -ne 1 ]; then
  exit 1
fi
