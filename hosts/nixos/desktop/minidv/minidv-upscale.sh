#!@bash@
# shellcheck shell=bash
set -euo pipefail

@minidvRuntime@

usage() {
  cat <<'USAGE'
Usage: minidv-upscale ABSOLUTE_TAPE_DIRECTORY

Create high-quality, non-AI upscaled intermediates from the verified raw-DV
master. Each inferred clip is field-rate deinterlaced, then enlarged twofold
with zimg Lanczos scaling and written as ProRes 422 HQ with PCM audio.

The original raw .dv master is read only. This command needs substantial free
space: conservatively 50 MB per source-second (about 132 GB for a 44-minute
tape) before it begins.
USAGE
}

fail() {
  printf 'minidv-upscale: %s\n' "$*" >&2
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
derivative_directory="$tape_directory/derivatives/upscaled/clips"

@minidvVerify@ "$tape_directory"

master_count=$(find "$master_directory" -maxdepth 1 -type f -name '*.dv' -printf . | wc -c)
if [ "$master_count" -ne 1 ]; then
  fail "expected exactly one verified raw .dv master, found $master_count."
fi
master=$(find "$master_directory" -maxdepth 1 -type f -name '*.dv' -print -quit)
tape_id=$(basename -- "$master" .dv)

if ! ffmpeg -hide_banner -filters 2>/dev/null | awk '$2 == "bwdif" { found = 1 } $2 == "zscale" { zscale = 1 } END { exit !(found && zscale) }'; then
  fail "this FFmpeg build must provide both bwdif and zscale."
fi
if ! ffmpeg -hide_banner -encoders 2>/dev/null | awk '$2 == "prores_ks" { found = 1 } END { exit !found }'; then
  fail "this FFmpeg build does not provide the prores_ks encoder."
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
probe_json="$logs_directory/upscale-probe-$stamp.json"
ffprobe -v error -show_format -show_streams -of json -- "$master" >"$probe_json"
source_width=$(jq -r '[.streams[]? | select(.codec_type == "video") | .width] | first // empty' "$probe_json")
source_height=$(jq -r '[.streams[]? | select(.codec_type == "video") | .height] | first // empty' "$probe_json")
source_sar=$(jq -r '[.streams[]? | select(.codec_type == "video") | .sample_aspect_ratio] | first // empty' "$probe_json")
source_dar=$(jq -r '[.streams[]? | select(.codec_type == "video") | .display_aspect_ratio] | first // "N/A"' "$probe_json")
source_duration=$(jq -r '.format.duration // empty' "$probe_json")
source_field_order=$(jq -r '[.streams[]? | select(.codec_type == "video") | .field_order] | first // "unknown"' "$probe_json")
audio_streams=$(jq '[.streams[]? | select(.codec_type == "audio")] | length' "$probe_json")

if ! [[ $source_width =~ ^[0-9]+$ && $source_height =~ ^[0-9]+$ && $source_sar =~ ^[0-9]+:[0-9]+$ ]]; then
  fail "could not determine a valid source width, height, and sample aspect ratio."
fi
if ! awk -v duration="$source_duration" 'BEGIN { exit !(duration > 0) }'; then
  fail "could not determine a positive source duration."
fi
if [ "$audio_streams" -lt 1 ]; then
  fail "the verified master has no audio stream; investigate capture before upscaling."
fi

target_width=$((source_width * 2))
target_height=$((source_height * 2))
target_sar=${source_sar/:/\/}
# ProRes 422 HQ at doubled spatial resolution and field rate is large. This
# conservative estimate prevents filling a filesystem in the middle of a tape.
required_bytes=$(awk -v duration="$source_duration" 'BEGIN { printf "%.0f", duration * 50000000 }')

umask 077
mkdir -p -- "$derivative_directory"
available_bytes=$(df -PB1 -- "$derivative_directory" | awk 'NR == 2 { print $4 }')
if ! [[ $available_bytes =~ ^[0-9]+$ ]] || [ "$available_bytes" -lt "$required_bytes" ]; then
  fail "need at least $required_bytes free bytes for ProRes intermediates; only ${available_bytes:-unknown} are available under '$derivative_directory'."
fi

exec 9>"$tape_directory/.minidv-upscale.lock"
if ! flock -n 9; then
  fail "another MiniDV upscale is already using '$tape_directory'."
fi

time_zone=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
time_zone=${time_zone:-UTC}
if ! TZ="$time_zone" date -d '2000-01-01 00:00' +%s >/dev/null 2>&1; then
  fail "desktop time zone '$time_zone' is not usable by date."
fi
manifest=$(MINIDV_TIME_ZONE="$time_zone" @minidvClipManifest@ "$tape_directory")
[ -s "$manifest" ] || fail "clip manifest was not created successfully."

run_directory="$derivative_directory/$stamp"
[ ! -e "$run_directory" ] || fail "refusing to overwrite existing upscale run '$run_directory'."
mkdir -p -- "$run_directory"
cp -- "$manifest" "$run_directory/clip-manifest.tsv"

{
  printf 'upscale_started_at_utc=%s\n' "$(date -u --iso-8601=seconds)"
  printf 'master=%s\n' "$master"
  printf 'source_dimensions=%sx%s\n' "$source_width" "$source_height"
  printf 'source_sar=%s\n' "$source_sar"
  printf 'source_dar=%s\n' "$source_dar"
  printf 'source_field_order=%s\n' "$source_field_order"
  printf 'output_dimensions=%sx%s\n' "$target_width" "$target_height"
  printf 'output_sar=%s\n' "$source_sar"
  printf 'output_dar=%s\n' "$source_dar"
  printf 'video_filter=bwdif=mode=send_field:parity=auto:deint=all,zscale=w=%s:h=%s:filter=lanczos,setsar=%s\n' "$target_width" "$target_height" "$target_sar"
  printf 'video_encoder=prores_ks profile=3 (ProRes 422 HQ)\n'
  printf 'audio_encoder=pcm_s16le\n'
  printf 'storage_estimate_bytes=%s\n' "$required_bytes"
  printf 'metadata_note=DV recording dates are inferred camera-local values and require visual review before being considered authoritative.\n'
} >"$run_directory/upscale-info.txt"

printf 'Source: %sx%s SAR %s DAR %s; field order=%s\n' "$source_width" "$source_height" "$source_sar" "$source_dar" "$source_field_order"
printf 'Upscaling to %sx%s with SAR %s, preserving displayed DAR %s.\n' "$target_width" "$target_height" "$source_sar" "$source_dar"
printf '%s\n' 'Creating per-clip ProRes 422 HQ / PCM intermediates. The raw DV master is not altered.'

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

  output="$run_directory/$tape_id-clip-$clip_id-$date_label.mov"
  partial_output="$run_directory/$tape_id-clip-$clip_id-$date_label.part.mov"
  ffmpeg_log="$logs_directory/upscale-$stamp-clip-$clip_id.log"
  result_probe="$logs_directory/upscale-result-$stamp-clip-$clip_id.json"
  [ ! -e "$output" ] && [ ! -e "$partial_output" ] || fail "refusing to overwrite an existing intermediate or partial file for clip $clip_id."

  printf 'Upscaling clip %s: %s → %s (%s; %s; %s)\n' \
    "$clip_id" "$start" "$end" "$recording_date" "$date_confidence" "$notes"

  metadata=(
    -metadata "title=$tape_id clip $clip_id"
    -metadata "comment=Upscaled from a verified MiniDV master using bwdif field-rate deinterlacing and zimg Lanczos scaling. Recording date is inferred from DV subcode."
  )
  if [ "$recording_date" != unknown ]; then
    metadata+=(
      -metadata "creation_time=$recorded_timestamp"
      -metadata "com.apple.quicktime.creationdate=$recorded_timestamp"
    )
  fi

  ffmpeg -nostdin -hide_banner -n -ss "$start" -t "$duration" -i "$master" \
    -map 0:v:0 -map '0:a?' \
    -vf "bwdif=mode=send_field:parity=auto:deint=all,zscale=w=$target_width:h=$target_height:filter=lanczos,setsar=$target_sar" \
    -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le \
    -c:a pcm_s16le \
    "${metadata[@]}" \
    -movflags +faststart+use_metadata_tags \
    "$partial_output" 2>&1 | tee "$ffmpeg_log"

  [ -s "$partial_output" ] || fail "FFmpeg produced no intermediate for clip $clip_id; retained any partial output for inspection."
  ffprobe -v error -show_format -show_streams -of json -- "$partial_output" >"$result_probe"
  output_codec=$(jq -r '[.streams[]? | select(.codec_type == "video") | .codec_name] | first // empty' "$result_probe")
  output_width=$(jq -r '[.streams[]? | select(.codec_type == "video") | .width] | first // empty' "$result_probe")
  output_height=$(jq -r '[.streams[]? | select(.codec_type == "video") | .height] | first // empty' "$result_probe")
  output_sar=$(jq -r '[.streams[]? | select(.codec_type == "video") | .sample_aspect_ratio] | first // empty' "$result_probe")
  output_dar=$(jq -r '[.streams[]? | select(.codec_type == "video") | .display_aspect_ratio] | first // empty' "$result_probe")
  output_audio_streams=$(jq '[.streams[]? | select(.codec_type == "audio")] | length' "$result_probe")
  apple_creation_date=$(jq -r '.format.tags["com.apple.quicktime.creationdate"] // empty' "$result_probe")

  if [ "$output_codec" != prores ] || [ "$output_width" != "$target_width" ] || [ "$output_height" != "$target_height" ] || [ "$output_sar" != "$source_sar" ] || [ "$output_dar" != "$source_dar" ]; then
    fail "clip $clip_id did not retain expected ProRes geometry; retained partial output."
  fi
  if [ "$output_audio_streams" -lt 1 ] || [ "$output_audio_streams" -gt "$audio_streams" ]; then
    fail "clip $clip_id has an unexpected audio-stream count; retained partial output."
  fi
  if [ "$recording_date" != unknown ] && [ "$apple_creation_date" != "$recorded_timestamp" ]; then
    fail "clip $clip_id did not retain its expected Apple creation-date metadata; retained partial output."
  fi

  mv -- "$partial_output" "$output"
  (cd "$run_directory" && sha256sum -- "$(basename "$output")") >"$output.sha256"
done <"$manifest"

[ "$clip_count" -gt 0 ] || fail "the clip manifest contained no usable clips; no intermediates were created."
(cd "$run_directory" && sha256sum -- ./*.mov) >"$run_directory/SHA256SUMS"
printf 'Created %s high-quality upscaled intermediate(s) in %s\n' "$clip_count" "$run_directory"
printf '%s\n' 'Review representative clips before making delivery MP4s. These are optional derivatives; retain the raw DV master and its independently verified backups.'
