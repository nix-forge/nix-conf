# shellcheck shell=bash
set -euo pipefail
mode=${1:?Expected lock or running}
shift
: "${XDG_RUNTIME_DIR:?A user runtime directory is required}"
: "${WAYLAND_DISPLAY:?A Wayland display is required}"

# A runtime file scopes the launch to this user and compositor connection.
# flock holds it until the locker exits, including after a crash. No process
# name, PID file, or stale file can suppress another session's lock request.
umask 077
display_key=$(printf '%s' "$WAYLAND_DISPLAY" | sha256sum)
lock_file="$XDG_RUNTIME_DIR/desktop-session-lock-${display_key%% *}.lock"

case "$mode" in
lock)
  # A concurrent request is already being handled. The locker still uses
  # ext-session-lock-v1 to acquire the real lock and notify Hypridle.
  exec flock --nonblock --conflict-exit-code 0 --close "$lock_file" "$@"
  ;;
running)
  # This checks our launch lifetime, not protocol acknowledgement. Only
  # Hypridle's lock notification is allowed to release its sleep inhibitor.
  if flock --nonblock --conflict-exit-code 75 "$lock_file" true; then
    exit 1
  else
    result=$?
    [[ $result == 75 ]]
  fi
  ;;
*)
  echo "Expected lock or running" >&2
  exit 2
  ;;
esac
