# shellcheck shell=bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: minidv-clip-manifest ABSOLUTE_TAPE_DIRECTORY

Create a reviewable TSV manifest of likely recording sessions in one verified
MiniDV capture. The raw .dv master is read only. Candidate cuts are derived
from the continuous dvgrab .srt0 sidecar, which contains the DV recording
date/time associated with positions in the complete capture timeline.
USAGE
}

fail() {
  printf 'minidv-clip-manifest: %s\n' "$*" >&2
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
metadata_directory="$tape_directory/metadata"

[ -d "$master_directory" ] || fail "missing master directory '$master_directory'."
[ -d "$metadata_directory" ] || fail "missing metadata directory '$metadata_directory'."

shopt -s nullglob
masters=("$master_directory"/*.dv)
if [ "${#masters[@]}" -ne 1 ]; then
  fail "expected exactly one raw .dv master, found ${#masters[@]}."
fi
master=${masters[0]}

source_duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 -- "$master")
if ! awk -v value="$source_duration" 'BEGIN { exit !(value > 0) }'; then
  fail "could not determine a positive duration for '$master'."
fi

# srt0 uses the continuous capture timeline. srt1 can reset at timecode
# discontinuities and is deliberately not suitable for splitting the master.
sidecars=("$metadata_directory"/*.srt0)
if [ "${#sidecars[@]}" -gt 1 ]; then
  fail "found multiple .srt0 sidecars; inspect the capture manually rather than choosing one automatically."
fi

time_zone=${MINIDV_TIME_ZONE:-}
if [ -z "$time_zone" ]; then
  time_zone=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
fi
time_zone=${time_zone:-UTC}
if ! TZ="$time_zone" date -d '2000-01-01 00:00' +%s >/dev/null 2>&1; then
  fail "'$time_zone' is not a usable IANA time zone. Set MINIDV_TIME_ZONE to one such as America/Los_Angeles."
fi

capture_started=$(awk -F= '$1 == "started_at" { print $2; exit }' "$metadata_directory/capture-info.txt" 2>/dev/null || true)
if [ -n "$capture_started" ] && capture_epoch=$(date -d "$capture_started" +%s 2>/dev/null); then
  # A camera timestamp in the future relative to capture is not credible. A
  # one-day allowance avoids rejecting a tape captured around midnight.
  latest_credible_epoch=$((capture_epoch + 86400))
else
  latest_credible_epoch=$(($(date +%s) + 86400))
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
manifest="$metadata_directory/clip-manifest-$stamp.tsv"
[ ! -e "$manifest" ] || fail "refusing to overwrite existing manifest '$manifest'."
temporary_entries=$(mktemp -- "$metadata_directory/.clip-manifest-entries.XXXXXX")
trap 'rm -f -- "$temporary_entries"' EXIT

if [ "${#sidecars[@]}" -eq 1 ]; then
  awk '
    /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9],[0-9][0-9][0-9] --> [0-9][0-9]:[0-9][0-9]:[0-9][0-9],[0-9][0-9][0-9]$/ {
      start = $1
      end = $3
      expect_date = 1
      next
    }
    expect_date && /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]$/ {
      print start "\t" end "\t" $0
      expect_date = 0
    }
  ' "${sidecars[0]}" >"$temporary_entries"
fi

seconds_from_srt() {
  awk -F '[:,.]' '{ printf "%.3f", ($1 * 3600) + ($2 * 60) + $3 + ($4 / 1000) }' <<<"$1"
}

numeric_greater_than() {
  awk -v left="$1" -v right="$2" 'BEGIN { exit !(left > right) }'
}

numeric_absolute_difference_exceeds() {
  awk -v left="$1" -v right="$2" -v limit="$3" 'BEGIN { delta = left - right; if (delta < 0) delta = -delta; exit !(delta > limit) }'
}

segment_starts=(0.000)
segment_dates=("unknown")
segment_confidence=("untrusted-date")
segment_notes=("No credible DV recording date was available at the beginning of this range.")

if [ -s "$temporary_entries" ]; then
  previous_timeline=""
  previous_recorded_epoch=""
  while IFS=$'\t' read -r start_srt end_srt recording_date; do
    timeline_start=$(seconds_from_srt "$start_srt")
    timeline_end=$(seconds_from_srt "$end_srt")
    entry_duration=$(awk -v end="$timeline_end" -v start="$timeline_start" 'BEGIN { printf "%.3f", end - start }')

    # Zero/near-zero entries commonly occur at a tape metadata glitch. They
    # are evidence retained in the sidecar, but not a defensible clip date.
    if ! numeric_greater_than "$entry_duration" 1; then
      continue
    fi
    if ! recorded_epoch=$(TZ="$time_zone" date -d "$recording_date" +%s 2>/dev/null); then
      continue
    fi
    if [ "$recorded_epoch" -gt "$latest_credible_epoch" ]; then
      continue
    fi

    if [ -z "$previous_timeline" ]; then
      # Preserve an opening region whose clock is invalid as its own clip;
      # never assign it a made-up date.
      # A sidecar commonly begins a frame or two after capture start.  Treat
      # sub-half-second offsets as part of the opening clip: preserving a
      # 33 ms "unknown" clip is neither useful nor a real recording boundary.
      if numeric_greater_than "$timeline_start" 0.5; then
        segment_starts+=("$timeline_start")
        segment_dates+=("$recording_date")
        segment_confidence+=("inferred-dv-date")
        segment_notes+=("First credible DV date after an untrusted opening range.")
      else
        segment_dates[0]=$recording_date
        segment_confidence[0]=inferred-dv-date
        segment_notes[0]="DV recording date inferred from the first credible timestamp."
      fi
    else
      timeline_elapsed=$(awk -v now="$timeline_start" -v before="$previous_timeline" 'BEGIN { printf "%.3f", now - before }')
      recorded_elapsed=$((recorded_epoch - previous_recorded_epoch))
      # Sidecar dates have one-minute precision. A 90-second tolerance avoids
      # treating ordinary rounding as a cut, while recognizing a genuine stop,
      # restart, date reset, or other major recording-clock discontinuity.
      if numeric_absolute_difference_exceeds "$recorded_elapsed" "$timeline_elapsed" 90; then
        segment_starts+=("$timeline_start")
        segment_dates+=("$recording_date")
        segment_confidence+=("inferred-dv-date")
        segment_notes+=("DV recording clock discontinuity greater than 90 seconds.")
      fi
    fi

    previous_timeline=$timeline_start
    previous_recorded_epoch=$recorded_epoch
  done <"$temporary_entries"
fi

{
  printf '# MiniDV candidate clip manifest v1\n'
  printf '# generated_at_utc=%s\n' "$(date -u --iso-8601=seconds)"
  printf '# master=%s\n' "$master"
  printf '# source_duration_seconds=%s\n' "$source_duration"
  printf '# source_srt0=%s\n' "${sidecars[0]:-none}"
  printf '# time_zone_assumption=%s\n' "$time_zone"
  printf '# recording_date_note=DV camera times are inferred local wall-clock values; review candidate cuts before treating dates as authoritative.\n'
  printf 'clip_id\tstart_seconds\tend_seconds\tduration_seconds\trecording_date_local\tdate_confidence\tnotes\n'

  for index in "${!segment_starts[@]}"; do
    start=${segment_starts[index]}
    if [ "$index" -lt $((${#segment_starts[@]} - 1)) ]; then
      end=${segment_starts[index + 1]}
    else
      end=$source_duration
    fi
    duration=$(awk -v end="$end" -v start="$start" 'BEGIN { printf "%.3f", end - start }')
    if ! numeric_greater_than "$duration" 0.5; then
      fail "derived a non-positive clip duration at candidate ${index}; retained no manifest."
    fi
    printf '%03d\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      $((index + 1)) "$start" "$end" "$duration" "${segment_dates[index]:-}" \
      "${segment_confidence[index]}" "${segment_notes[index]}"
  done
} >"$manifest"

printf '%s\n' "$manifest"
