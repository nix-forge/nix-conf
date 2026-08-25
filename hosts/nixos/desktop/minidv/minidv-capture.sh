#!@bash@
# shellcheck shell=bash
set -euo pipefail

@minidvRuntime@

usage() {
  cat <<'USAGE'
Usage: minidv-capture TAPE_ID ABSOLUTE_ARCHIVE_DIRECTORY

Capture one MiniDV tape as an untouched raw-DV master. The destination must
not already contain the requested tape ID. Interrupting capture preserves all
partial files and marks the capture as incomplete; it never deletes or
overwrites a capture.
USAGE
}

fail() {
  printf 'minidv-capture: %s\n' "$*" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 2
fi

tape_id=$1
archive_directory=$2

if [[ ! $tape_id =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; then
  fail "TAPE_ID must be 1-64 characters of letters, digits, '_' or '-'."
fi

case "$archive_directory" in
/*) ;;
*) fail "ABSOLUTE_ARCHIVE_DIRECTORY must be an absolute path." ;;
esac

mkdir -p -- "$archive_directory"
archive_directory=$(realpath -e -- "$archive_directory")
tape_directory="$archive_directory/$tape_id"
master_directory="$tape_directory/master"
logs_directory="$tape_directory/logs"
metadata_directory="$tape_directory/metadata"
final_master="$master_directory/$tape_id.dv"
capture_base="$master_directory/$tape_id"
capture_log="$logs_directory/capture.log"
capture_metadata="$metadata_directory/capture-info.txt"

if [ -e "$tape_directory" ]; then
  fail "refusing to use existing tape directory '$tape_directory'; choose a new ID or inspect the existing capture manually."
fi

# DV is about 13 GiB/hour.  Reserve a conservative 20 GiB before creating the
# capture directory so a nominal one-hour tape does not run the filesystem dry.
minimum_free_kib=$((20 * 1024 * 1024))
available_kib=$(df -Pk -- "$archive_directory" | awk 'NR == 2 { print $4 }')
case "$available_kib" in
'' | *[!0-9]*) fail "could not determine available space for '$archive_directory'." ;;
esac
if [ "$available_kib" -lt "$minimum_free_kib" ]; then
  fail "only $((available_kib / 1024 / 1024)) GiB is free; require at least 20 GiB before capture."
fi

shopt -s nullglob
firewire_nodes=(/dev/fw*)
if [ "${#firewire_nodes[@]}" -eq 0 ]; then
  fail "no /dev/fw* controller node exists. Install/verify the PCIe card before capture. Run minidv-diagnose."
fi

accessible_nodes=()
for node in "${firewire_nodes[@]}"; do
  if [ -r "$node" ] && [ -w "$node" ]; then
    accessible_nodes+=("$node")
  fi
done
if [ "${#accessible_nodes[@]}" -eq 0 ]; then
  printf '%s\n' "minidv-capture: no FireWire controller node is accessible to $(id -un)." >&2
  ls -l -- "${firewire_nodes[@]}" >&2 || true
  getfacl -p -- "${firewire_nodes[@]}" >&2 || true
  fail "do not change permissions manually; inspect the device with minidv-diagnose and add a narrow rule only if needed."
fi

firewire_sysfs=/sys/bus/firewire/devices
remote_nodes=()
if [ -d "$firewire_sysfs" ]; then
  for device in "$firewire_sysfs"/fw*; do
    [ -r "$device/is_local" ] || continue
    if [ "$(cat "$device/is_local")" = 0 ]; then
      remote_nodes+=("$device")
    fi
  done
fi
if [ "${#remote_nodes[@]}" -eq 0 ]; then
  fail "no remote FireWire node was found. Connect the AC-powered camcorder in VCR/playback mode, then run minidv-diagnose."
fi

# dvgrab's automatic libraw1394 device discovery is unreliable with the
# current firewire-cdev stack: it can see the bus but report "invalid source
# specified".  The camera's live FireWire GUID is the stable selector that
# dvgrab itself supports.  Refuse ambiguity rather than accidentally capture
# from a different connected DV device.
if [ "${#remote_nodes[@]}" -ne 1 ]; then
  fail "found ${#remote_nodes[@]} remote FireWire nodes; disconnect other FireWire devices so the camcorder can be selected unambiguously."
fi
camera_guid=$(cat "${remote_nodes[0]}/guid")
case "$camera_guid" in
0x[0-9a-fA-F][0-9a-fA-F]*) camera_guid=${camera_guid#0x} ;;
*) fail "could not read a valid GUID for remote FireWire node '$(basename "${remote_nodes[0]}")'. Run minidv-diagnose." ;;
esac

umask 077
mkdir -p -- "$master_directory" "$logs_directory" "$metadata_directory"
exec 9>"$archive_directory/.minidv-capture.lock"
if ! flock -n 9; then
  fail "another MiniDV capture is already using '$archive_directory'."
fi

write_firewire_inventory() {
  for device in "$firewire_sysfs"/fw*; do
    [ -e "$device" ] || continue
    printf 'firewire_node=%s\n' "$(basename "$device")"
    for attribute in is_local guid vendor model units; do
      if [ -r "$device/$attribute" ]; then
        printf 'firewire_%s_%s=%s\n' "$(basename "$device")" "$attribute" "$(cat "$device/$attribute")"
      fi
    done
  done
}

capture_started=$(date --iso-8601=seconds)
{
  printf 'capture_state=started\n'
  printf 'tape_id=%s\n' "$tape_id"
  printf 'started_at=%s\n' "$capture_started"
  printf 'host=%s\n' "$(hostname)"
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'archive_root=%s\n' "$archive_directory"
  printf 'free_space_before_kib=%s\n' "$available_kib"
  printf 'camera_guid=%s\n' "$camera_guid"
  printf 'capture_command=dvgrab --guid <camera-guid> --format raw --size 0 --frames 0 --showstatus --srt --noavc --nostop <base>\n'
  printf 'autosplit=disabled\n'
  write_firewire_inventory
} >"$capture_metadata"

camera_lost_marker="$metadata_directory/camera-disconnected"

selected_camera_is_present() {
  local device guid
  for device in "$firewire_sysfs"/fw*; do
    [ -r "$device/is_local" ] || continue
    [ "$(cat "$device/is_local")" = 0 ] || continue
    [ -r "$device/guid" ] || continue
    guid=$(cat "$device/guid")
    if [ "$guid" = "0x$camera_guid" ]; then
      return 0
    fi
  done
  return 1
}

watch_selected_camera() {
  # A paused tape remains on the bus and is valid: do not impose an arbitrary
  # no-frame timeout.  A missing remote node is different; continuing would
  # only leave dvgrab waiting forever after a bus reset or disconnect.
  while kill -0 "$dvgrab_pid" 2>/dev/null; do
    if ! selected_camera_is_present; then
      printf '%s\n' 'minidv-capture: selected camera disappeared from the FireWire bus; stopping the incomplete capture.' |
        tee -a "$capture_log" >&2
      : >"$camera_lost_marker"
      kill -TERM "$dvgrab_pid" 2>/dev/null || true
      return
    fi
    sleep 1
  done
}

interrupted() {
  trap - INT TERM HUP
  if [ -n "${dvgrab_pid:-}" ] && kill -0 "$dvgrab_pid" 2>/dev/null; then
    printf '\nStopping dvgrab and retaining the partial capture...\n' >&2
    kill -INT "$dvgrab_pid" 2>/dev/null || true
    for _ in {1..5}; do
      kill -0 "$dvgrab_pid" 2>/dev/null || break
      sleep 1
    done

    if kill -0 "$dvgrab_pid" 2>/dev/null; then
      printf 'dvgrab did not exit after SIGINT; sending SIGTERM...\n' >&2
      kill -TERM "$dvgrab_pid" 2>/dev/null || true
      for _ in {1..5}; do
        kill -0 "$dvgrab_pid" 2>/dev/null || break
        sleep 1
      done
    fi

    if kill -0 "$dvgrab_pid" 2>/dev/null; then
      printf 'dvgrab is unresponsive; force-stopping it without removing captured data.\n' >&2
      kill -KILL "$dvgrab_pid" 2>/dev/null || true
    fi
  fi
  printf 'capture_state=interrupted\ninterrupted_at=%s\n' "$(date --iso-8601=seconds)" >>"$capture_metadata"
  printf '\nCapture interrupted. Partial files were deliberately retained in %s.\n' "$tape_directory" >&2
  exit 130
}
trap interrupted INT TERM HUP

printf '%s\n' "Starting raw DV capture for '$tape_id'. Press Play on the camcorder yourself after dvgrab reports that it is waiting for DV."
printf '%s\n' "dvgrab will not send AV/C play or stop commands to the camcorder."
printf '%s\n' "Using detected camera FireWire GUID: $camera_guid"
printf '%s\n' "DV over FireWire has no reliable tape-end signal: dvgrab cannot distinguish a paused tape from its physical end."
printf '%s\n' "When the camcorder reaches its physical end, press Ctrl-C once. It retains the capture without deleting data; then run minidv-finalize --confirm-tape-ended on that tape directory."

# Keep dvgrab as a direct child of this wrapper.  Bash defers signal traps
# while a foreground pipeline is running, which can leave an unresponsive
# dvgrab capture unable to react to Ctrl-C.  A background child plus wait lets
# the trap stop precisely that child and preserve a clear incomplete state.
dvgrab --guid "$camera_guid" --format raw --size 0 --frames 0 --showstatus --srt --noavc --nostop "$capture_base" \
  > >(tee -a "$capture_log") 2>&1 &
dvgrab_pid=$!
watch_selected_camera &
camera_watchdog_pid=$!
set +e
wait "$dvgrab_pid"
dvgrab_status=$?
kill "$camera_watchdog_pid" 2>/dev/null || true
wait "$camera_watchdog_pid" 2>/dev/null || true
set -e
dvgrab_pid=""
capture_finished=$(date --iso-8601=seconds)

if [ -e "$camera_lost_marker" ]; then
  printf 'capture_state=camera-disconnected\nended_at=%s\ndvgrab_exit_status=%s\n' \
    "$capture_finished" "$dvgrab_status" >>"$capture_metadata"
  fail "the selected camera disappeared from the FireWire bus; retained any partial data in '$tape_directory'. Reconnect and verify it with minidv-diagnose before retrying."
fi

if [ "$dvgrab_status" -ne 0 ]; then
  printf 'capture_state=dvgrab-failed\nended_at=%s\ndvgrab_exit_status=%s\n' "$capture_finished" "$dvgrab_status" >>"$capture_metadata"
  fail "dvgrab failed; any partial data was retained in '$tape_directory'."
fi

captures=("$master_directory"/*.dv)
if [ "${#captures[@]}" -ne 1 ]; then
  printf 'capture_state=unexpected-output\nended_at=%s\nraw_dv_files=%s\n' "$capture_finished" "${#captures[@]}" >>"$capture_metadata"
  fail "expected exactly one raw DV file with autosplit disabled; retained all output for inspection."
fi

if [ -e "$final_master" ]; then
  fail "refusing to overwrite existing master '$final_master'."
fi
mv -- "${captures[0]}" "$final_master"

sidecars=("$master_directory"/*.srt0 "$master_directory"/*.srt1)
for sidecar in "${sidecars[@]}"; do
  [ -e "$sidecar" ] || continue
  mv -- "$sidecar" "$metadata_directory/$(basename "$sidecar")"
done

printf 'capture_state=complete-pending-verification\nended_at=%s\ndvgrab_exit_status=0\nmaster=%s\n' \
  "$capture_finished" "$final_master" >>"$capture_metadata"

# minidv-verify writes its own timestamped verification log. Keep capture.log
# reserved for dvgrab output so a verifier message can never be mistaken for a
# capture-time failure on a later verification.
if ! @minidvVerify@ "$tape_directory"; then
  printf 'capture_state=verification-failed\nverified_at=%s\n' "$(date --iso-8601=seconds)" >>"$capture_metadata"
  fail "capture was retained but did not pass verification; do not treat it as archived yet."
fi

printf 'capture_state=verified\nverified_at=%s\n' "$(date --iso-8601=seconds)" >>"$capture_metadata"
printf '\nCapture verified. Create and checksum-verify an independent second copy before treating this tape as preserved.\n'
