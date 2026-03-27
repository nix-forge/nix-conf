#!/usr/bin/env bash

set -euo pipefail

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

timestamp_id() {
  date -u +"%Y%m%dT%H%M%SZ"
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

retry_until_success() {
  local attempts=$1
  local delay=$2
  shift 2
  local n=1
  while true; do
    if "$@"; then
      return 0
    fi
    if ((n >= attempts)); then
      return 1
    fi
    n=$((n + 1))
    sleep "$delay"
  done
}

print_stage_table() {
  local -n _names=$1
  local -n _status=$2
  local -n _duration=$3
  local -n _reason=$4
  local i

  printf '%-24s %-6s %-8s %s\n' "STAGE" "STATE" "SECONDS" "REASON"
  for i in "${!_names[@]}"; do
    printf '%-24s %-6s %-8s %s\n' "${_names[$i]}" "${_status[$i]}" "${_duration[$i]}" "${_reason[$i]}"
  done
}

write_summary_files() {
  local out_dir=$1
  local profile=$2
  local total_seconds=$3
  local overall=$4
  local -n _names=$5
  local -n _status=$6
  local -n _duration=$7
  local -n _reason=$8

  {
    echo "profile: $profile"
    echo "finished_at: $(timestamp_utc)"
    echo "overall: $overall"
    echo "total_seconds: $total_seconds"
    echo
    printf '%-24s %-6s %-8s %s\n' "STAGE" "STATE" "SECONDS" "REASON"
    local i
    for i in "${!_names[@]}"; do
      printf '%-24s %-6s %-8s %s\n' "${_names[$i]}" "${_status[$i]}" "${_duration[$i]}" "${_reason[$i]}"
    done
  } >"$out_dir/summary.txt"

  {
    printf '{\n'
    printf '  "profile": "%s",\n' "$(json_escape "$profile")"
    printf '  "finished_at": "%s",\n' "$(json_escape "$(timestamp_utc)")"
    printf '  "overall": "%s",\n' "$(json_escape "$overall")"
    printf '  "total_seconds": %s,\n' "$total_seconds"
    printf '  "stages": [\n'
    local i
    for i in "${!_names[@]}"; do
      printf '    {"name":"%s","state":"%s","seconds":%s,"reason":"%s"}' \
        "$(json_escape "${_names[$i]}")" \
        "$(json_escape "${_status[$i]}")" \
        "${_duration[$i]}" \
        "$(json_escape "${_reason[$i]}")"
      if [[ $i -lt $((${#_names[@]} - 1)) ]]; then
        printf ','
      fi
      printf '\n'
    done
    printf '  ]\n'
    printf '}\n'
  } >"$out_dir/summary.json"
}
