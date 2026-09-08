#!/usr/bin/env bash
# Dependencies: a running Wayland session, Hyprland/hyprctl, cc, pkg-config,
# wayland-scanner, wayland development headers, wayland-protocols, and jq.
# Set HYPRLAND_TEST_HEADLESS=1 to create a headless output after IPC starts.
# Usage: bash tests/hyprland/check-subsurface-teardown.sh /path/to/Hyprland
set -euo pipefail

binary=${1:?Provide the Hyprland binary to test}
: "${WAYLAND_DISPLAY:?Run within a Wayland session}"
: "${XDG_RUNTIME_DIR:?A Wayland runtime directory is required}"
test_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work_directory=$(mktemp -d)
runtime_directory=$(mktemp -d /tmp/hc.XXXXXX)
compositor_pid=
cleanup() {
  if [[ -n $compositor_pid ]]; then
    kill -TERM -- "-$compositor_pid" 2>/dev/null || true
    sleep 0.2
    kill -KILL -- "-$compositor_pid" 2>/dev/null || true
    wait "$compositor_pid" 2>/dev/null || true
  fi
  if [[ ${KEEP_TEST_OUTPUT:-0} == 1 ]]; then
    echo "Test output: $work_directory"
    echo "Runtime output: $runtime_directory"
  else
    rm -rf -- "$work_directory"
    rm -rf -- "$runtime_directory"
  fi
}
trap cleanup EXIT

# Keep compositor sockets and systemd's private socket lookup in a separate
# runtime directory. The only connection to the real session is its Wayland
# socket, used as the parent display for the nested window.
parent_socket=$WAYLAND_DISPLAY
if [[ $parent_socket != /* ]]; then
  parent_socket="$XDG_RUNTIME_DIR/$parent_socket"
fi
# Hyprland embeds its long instance identifier in Unix socket paths. Keep the
# runtime path short enough for sockaddr_un's 108-byte limit.
export XDG_RUNTIME_DIR="$runtime_directory"
export WAYLAND_DISPLAY="$parent_socket"

protocol_directory=$(pkg-config --variable=pkgdatadir wayland-protocols)
wayland-scanner client-header "$protocol_directory/stable/xdg-shell/xdg-shell.xml" "$work_directory/xdg-shell-client-protocol.h"
wayland-scanner private-code "$protocol_directory/stable/xdg-shell/xdg-shell.xml" "$work_directory/xdg-shell-protocol.c"
wayland-scanner client-header "$protocol_directory/staging/color-management/color-management-v1.xml" "$work_directory/color-management-v1-client-protocol.h"
wayland-scanner private-code "$protocol_directory/staging/color-management/color-management-v1.xml" "$work_directory/color-management-v1-protocol.c"
read -r -a cflags <<<"$(pkg-config --cflags wayland-client)"
read -r -a ldflags <<<"$(pkg-config --libs wayland-client)"
cc "${cflags[@]}" -I"$work_directory" "$test_directory/subsurface-parent-teardown.c" "$work_directory/xdg-shell-protocol.c" "$work_directory/color-management-v1-protocol.c" "${ldflags[@]}" -o "$work_directory/client"

cat >"$work_directory/test.lua" <<'EOF'
hl.config({ animations = { enabled = false }, misc = { disable_watchdog_warning = true }, debug = { disable_logs = false } })
hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })
EOF

# Use a render node, which cannot control physical outputs, and prevent the nested compositor from
# changing the real session's systemd/D-Bus activation environment or targets.
render_device=${HYPRLAND_TEST_RENDER_DEVICE:-/dev/dri/renderD128}
[[ $render_device =~ ^/dev/dri/renderD[0-9]+$ && -c $render_device ]]
env AQ_DRM_DEVICES="$render_device" HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_TARGET=1 HYPRLAND_NO_SD_NOTIFY=1 \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$work_directory/no-session-bus" \
  XDG_CACHE_HOME="$work_directory/cache" XDG_STATE_HOME="$work_directory/state" \
  setsid "$binary" --config "$work_directory/test.lua" >"$work_directory/compositor.log" 2>&1 &
compositor_pid=$!
instance=
ready=0
headless_created=0
startup_deadline=$((SECONDS + 120))
while ((SECONDS < startup_deadline)); do
  instance=$(timeout 2 hyprctl instances -j 2>/dev/null | jq -r --argjson pid "$compositor_pid" '.[] | select(.pid == $pid) | .instance' 2>/dev/null) || instance=
  if [[ ${HYPRLAND_TEST_HEADLESS:-0} == 1 && -n $instance && $headless_created == 0 ]]; then
    if response=$(timeout 2 hyprctl -i "$instance" output create headless HEADLESS-TEST 2>/dev/null) && [[ $response == ok ]]; then
      headless_created=1
    fi
  fi
  if [[ -n $instance ]] && timeout 2 hyprctl -i "$instance" monitors -j 2>/dev/null | jq -e 'length > 0 and all(.[]; .name | startswith("WAYLAND-") or startswith("HEADLESS-"))' >/dev/null 2>&1; then
    ready=1
    break
  fi
  kill -0 "$compositor_pid"
  sleep 0.1
done
[[ $ready == 1 ]] || {
  echo 'FAIL: nested compositor did not start'
  exit 1
}
socket=$(timeout 2 hyprctl instances -j | jq -r --arg instance "$instance" '.[] | select(.instance == $instance) | .wl_socket')
[[ -n $socket && $socket != "$WAYLAND_DISPLAY" ]]
timeout 2 hyprctl -i "$instance" monitors -j | jq -e 'length > 0 and all(.[]; .name | startswith("WAYLAND-") or startswith("HEADLESS-"))' >/dev/null

read -r -a scenarios <<<"${HYPRLAND_TEST_SCENARIOS:-orphan disconnect feedback child-first}"
for scenario in "${scenarios[@]}"; do
  for iteration in {1..5}; do
    if ! WAYLAND_DISPLAY="$socket" timeout 10 "$work_directory/client" "$scenario"; then
      echo "FAIL: $scenario iteration $iteration disconnected during subsurface teardown"
      exit 1
    fi
    # A successful client exit alone cannot prove that disconnect cleanup
    # survived. Query the compositor after it has processed the disconnect.
    sleep 0.1
    kill -0 "$compositor_pid"
    timeout 2 hyprctl -i "$instance" version >/dev/null
  done
done

# Confirm the compositor can also complete an orderly shutdown after the
# teardown scenarios. Keep the EXIT trap as a bounded fallback.
timeout 2 hyprctl -i "$instance" dispatch 'hl.dsp.exit()' >/dev/null
shutdown_deadline=$((SECONDS + 10))
while kill -0 "$compositor_pid" 2>/dev/null && ((SECONDS < shutdown_deadline)); do
  sleep 0.1
done
if kill -0 "$compositor_pid" 2>/dev/null; then
  echo 'FAIL: compositor did not exit within 10 seconds'
  exit 1
fi
set +e
wait "$compositor_pid"
shutdown_status=$?
set -e
compositor_pid=
[[ $shutdown_status == 0 ]] || {
  echo "FAIL: compositor exited with status $shutdown_status"
  exit 1
}
echo 'PASS: compositor survived every selected subsurface lifecycle scenario and exited cleanly'
