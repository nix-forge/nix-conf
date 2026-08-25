#!@bash@
# shellcheck shell=bash
set -euo pipefail

@minidvRuntime@

usage() {
  cat <<'USAGE'
Usage: minidv-transcode ABSOLUTE_TAPE_DIRECTORY [--upscale-run ABSOLUTE_RUN_DIRECTORY]

Create separate Apple-friendly H.264/AAC MP4 viewing derivatives from a
verified raw-DV master. With --upscale-run, transcode the high-quality ProRes
intermediates created by minidv-upscale instead of making a direct DV viewing
copy. Candidate boundaries and dates are inferred from the continuous DV
recording-date sidecar. The raw .dv master is never modified.
USAGE
}

fail() {
  printf 'minidv-transcode: %s\n' "$*" >&2
  exit 1
}

if [ "$#" -ne 1 ] && { [ "$#" -ne 3 ] || [ "$2" != "--upscale-run" ]; }; then
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
upscale_run=${3:-}

@minidvVerify@ "$tape_directory"

master_count=$(find "$master_directory" -maxdepth 1 -type f -name '*.dv' -printf . | wc -c)
if [ "$master_count" -ne 1 ]; then
  fail "expected exactly one verified raw .dv master, found $master_count."
fi
master=$(find "$master_directory" -maxdepth 1 -type f -name '*.dv' -print -quit)
tape_id=$(basename -- "$master" .dv)

time_zone=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
if [ -z "$time_zone" ]; then
  time_zone=UTC
fi
if ! TZ="$time_zone" date -d '2000-01-01 00:00' +%s >/dev/null 2>&1; then
  fail "desktop time zone '$time_zone' is not usable by date."
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
probe_json="$logs_directory/transcode-probe-$stamp.json"
ffprobe -v error -show_format -show_streams -of json -- "$master" >"$probe_json"
source_dar=$(jq -r '[.streams[]? | select(.codec_type == "video") | .display_aspect_ratio] | first // "N/A"' "$probe_json")
source_field_order=$(jq -r '[.streams[]? | select(.codec_type == "video") | .field_order] | first // "unknown"' "$probe_json")
source_rate=$(jq -r '[.streams[]? | select(.codec_type == "video") | .avg_frame_rate] | first // "unknown"' "$probe_json")
audio_streams=$(jq '[.streams[]? | select(.codec_type == "audio")] | length' "$probe_json")

if [ "$audio_streams" -lt 1 ]; then
  fail "the verified master has no audio stream; investigate capture before making a viewing derivative."
fi
# Do not use grep -q here: with pipefail enabled it can close the pipe as
# soon as it sees libx264, leaving ffmpeg with SIGPIPE and turning a present
# encoder into a false-negative. awk consumes the complete encoder list.
if ! ffmpeg -hide_banner -encoders 2>/dev/null | awk '$2 == "libx264" { found = 1 } END { exit !found }'; then
  fail "this FFmpeg build does not provide libx264."
fi

umask 077
exec 9>"$tape_directory/.minidv-transcode.lock"
if ! flock -n 9; then
  fail "another MiniDV transcode is already using '$tape_directory'."
fi

# srt0 follows the continuous master timeline, unlike srt1 which may reset
# at tape timecode discontinuities. The manifest labels dates as inferred.
if [ -n "$upscale_run" ]; then
  case "$upscale_run" in
  /*) ;;
  *) fail "UPSCALE_RUN_DIRECTORY must be an absolute path." ;;
  esac
  upscale_run=$(realpath -e -- "$upscale_run")
  [ -d "$upscale_run" ] || fail "upscale run '$upscale_run' is not a directory."
  [ -f "$upscale_run/upscale-info.txt" ] || fail "upscale run lacks upscale-info.txt."
  [ -f "$upscale_run/clip-manifest.tsv" ] || fail "upscale run lacks clip-manifest.tsv."
  upscale_master=$(awk -F= '$1 == "master" { print substr($0, length($1) + 2); exit }' "$upscale_run/upscale-info.txt")
  [ "$upscale_master" = "$master" ] || fail "upscale run was not made from this tape's verified raw master."
  manifest="$upscale_run/clip-manifest.tsv"
  derivative_directory="$tape_directory/derivatives/apple/upscaled-clips"
  source_mode=upscaled-prores
else
  manifest=$(MINIDV_TIME_ZONE="$time_zone" @minidvClipManifest@ "$tape_directory")
  [ -s "$manifest" ] || fail "clip manifest was not created successfully."
  derivative_directory="$tape_directory/derivatives/apple/clips"
  source_mode=raw-dv
fi

mkdir -p -- "$derivative_directory"
run_directory="$derivative_directory/$stamp"
[ ! -e "$run_directory" ] || fail "refusing to overwrite existing derivative run '$run_directory'."
mkdir -p -- "$run_directory"
cp -- "$manifest" "$run_directory/clip-manifest.tsv"

{
  printf 'transcode_started_at_utc=%s\n' "$(date -u --iso-8601=seconds)"
  printf 'master=%s\n' "$master"
  printf 'source_dar=%s\n' "$source_dar"
  printf 'source_field_order=%s\n' "$source_field_order"
  printf 'source_rate=%s\n' "$source_rate"
  printf 'source_mode=%s\n' "$source_mode"
  if [ "$source_mode" = upscaled-prores ]; then
    printf 'upscale_run=%s\n' "$upscale_run"
  fi
  printf 'time_zone_assumption=%s\n' "$time_zone"
  printf 'metadata_note=DV recording dates are inferred camera-local values and require visual review before being considered authoritative.\n'
} >"$run_directory/transcode-info.txt"

printf 'Source: DAR=%s, field order=%s, frame rate=%s\n' "$source_dar" "$source_field_order" "$source_rate"
printf 'Candidate clips use DV recording-clock discontinuities from %s.\n' "$manifest"
printf 'Using desktop time-zone assumption %s for QuickTime creation metadata.\n' "$time_zone"
if [ "$source_mode" = raw-dv ]; then
  printf '%s\n' 'Creating progressive H.264/AAC derivatives with bwdif field-rate deinterlacing. The raw DV master is not altered.'
else
  printf '%s\n' 'Creating high-quality H.264/AAC delivery derivatives from the validated ProRes upscale intermediates. The raw DV master is not altered.'
fi

clip_count=0
while IFS=$'\t' read -r clip_id start end duration recording_date date_confidence notes; do
  case "$clip_id" in
  [0-9][0-9][0-9]) ;;
  *) continue ;;
  esac
  clip_count=$((clip_count + 1))

  if [ "$recording_date" = unknown ]; then
    date_label=unknown-date
    recorded_timestamp=""
  else
    recorded_timestamp=$(TZ="$time_zone" date -d "$recording_date" --iso-8601=seconds)
    date_label=$(printf '%s' "$recording_date" | tr ' :' 'T-')
  fi

  output="$run_directory/$tape_id-clip-$clip_id-$date_label.mp4"
  partial_output="$run_directory/$tape_id-clip-$clip_id-$date_label.part.mp4"
  ffmpeg_log="$logs_directory/transcode-$stamp-clip-$clip_id.log"
  result_probe="$logs_directory/transcode-result-$stamp-clip-$clip_id.json"

  [ ! -e "$output" ] && [ ! -e "$partial_output" ] || fail "refusing to overwrite an existing derivative or partial file for clip $clip_id."
  printf 'Transcoding clip %s: %s → %s (%s; %s; %s)\n' \
    "$clip_id" "$start" "$end" "$recording_date" "$date_confidence" "$notes"

  # DV is intra-frame, so input seeking is frame-addressable while avoiding
  # repeated decoding of all earlier clips. Every output is freshly encoded;
  # no lossy stream-copy cut is made from the preservation master. The upscale
  # path deliberately does not deinterlace or scale a second time.
  if [ "$source_mode" = raw-dv ]; then
    input="$master"
    source_arguments=(-ss "$start" -t "$duration")
    filter_arguments=(-vf 'bwdif=mode=send_field:parity=auto:deint=all')
    video_arguments=(-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p)
  else
    input="$upscale_run/$tape_id-clip-$clip_id-$date_label.mov"
    [ -s "$input" ] || fail "upscaled ProRes intermediate for clip $clip_id is missing: '$input'."
    input_codec=$(ffprobe -v error -show_streams -of json -- "$input" | jq -r '[.streams[]? | select(.codec_type == "video") | .codec_name] | first // empty')
    [ "$input_codec" = prores ] || fail "upscaled input for clip $clip_id is not ProRes."
    source_arguments=()
    filter_arguments=()
    # CRF 16 minimizes the one intentional delivery encode after the ProRes
    # intermediate. H.264/yuv420p maximizes Apple Photos compatibility.
    video_arguments=(-c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p)
  fi

  if [ "$recording_date" = unknown ]; then
    ffmpeg -nostdin -hide_banner -n "${source_arguments[@]}" -i "$input" \
      -map 0:v:0 -map '0:a?' \
      "${filter_arguments[@]}" \
      "${video_arguments[@]}" \
      -c:a aac -b:a 192k \
      -metadata "title=$tape_id clip $clip_id" \
      -metadata "comment=Derived from a verified MiniDV master. The DV recording date for this range was untrusted; no creation date was assigned." \
      -movflags +faststart+use_metadata_tags \
      "$partial_output" 2>&1 | tee "$ffmpeg_log"
  else
    ffmpeg -nostdin -hide_banner -n "${source_arguments[@]}" -i "$input" \
      -map 0:v:0 -map '0:a?' \
      "${filter_arguments[@]}" \
      "${video_arguments[@]}" \
      -c:a aac -b:a 192k \
      -metadata "title=$tape_id clip $clip_id" \
      -metadata "creation_time=$recorded_timestamp" \
      -metadata "com.apple.quicktime.creationdate=$recorded_timestamp" \
      -metadata "comment=Derived from a verified MiniDV master; recording date inferred from DV subcode. Camera-local time converted using $time_zone." \
      -movflags +faststart+use_metadata_tags \
      "$partial_output" 2>&1 | tee "$ffmpeg_log"
  fi

  [ -s "$partial_output" ] || fail "FFmpeg produced no derivative for clip $clip_id; retained any partial output for inspection."
  ffprobe -v error -show_format -show_streams -of json -- "$partial_output" >"$result_probe"
  derivative_video=$(jq -r '[.streams[]? | select(.codec_type == "video") | .codec_name] | first // empty' "$result_probe")
  derivative_audio=$(jq -r '[.streams[]? | select(.codec_type == "audio") | .codec_name] | first // empty' "$result_probe")
  derivative_audio_streams=$(jq '[.streams[]? | select(.codec_type == "audio")] | length' "$result_probe")
  derivative_dar=$(jq -r '[.streams[]? | select(.codec_type == "video") | .display_aspect_ratio] | first // "N/A"' "$result_probe")
  apple_creation_date=$(jq -r '.format.tags["com.apple.quicktime.creationdate"] // empty' "$result_probe")

  if [ "$derivative_video" != h264 ] || [ "$derivative_audio" != aac ]; then
    fail "clip $clip_id validation expected H.264/AAC, got video=$derivative_video audio=$derivative_audio; retained partial output."
  fi
  # This tape's second DV audio track is sparse: it is mapped whenever packets
  # exist in a clip, but FFmpeg correctly omits it from ranges where it has no
  # frames. Require usable audio, not an identical stream count per clip.
  if [ "$derivative_audio_streams" -lt 1 ]; then
    fail "clip $clip_id has no encoded audio stream; retained partial output."
  fi
  if [ "$derivative_audio_streams" -gt "$audio_streams" ]; then
    fail "clip $clip_id has more audio streams than the master; retained partial output."
  fi
  if [ "$source_dar" != N/A ] && [ "$derivative_dar" != "$source_dar" ]; then
    fail "clip $clip_id DAR '$derivative_dar' differs from source DAR '$source_dar'; retained partial output."
  fi
  if [ "$recording_date" != unknown ] && [ "$apple_creation_date" != "$recorded_timestamp" ]; then
    fail "clip $clip_id did not retain its expected Apple creation-date metadata; retained partial output."
  fi

  mv -- "$partial_output" "$output"
  (cd "$run_directory" && sha256sum -- "$(basename "$output")") >"$output.sha256"
done <"$manifest"

[ "$clip_count" -gt 0 ] || fail "the clip manifest contained no usable clips; no derivatives were created."
(cd "$run_directory" && sha256sum -- ./*.mp4) >"$run_directory/SHA256SUMS"
printf 'Created %s candidate clip derivative(s) in %s\n' "$clip_count" "$run_directory"
printf '%s\n' 'Review each manifest boundary and date before importing clips into Apple Photos. Keep the raw .dv master and its independently verified backups outside Photos.'
