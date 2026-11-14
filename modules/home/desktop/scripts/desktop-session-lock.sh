# shellcheck shell=bash
set -euo pipefail
mode=${1:?Expected lock, recover, or running}
case "$mode" in
lock | recover)
  : "${WAYLAND_DISPLAY:?A Wayland display is required}"
  unit="$(@systemd_escape@ --template=@unit_template@ "$WAYLAND_DISPLAY")"
  if [[ $mode == lock ]]; then
    exec @systemctl@ --user start "$unit"
  fi
  # Recovery is an explicit operator action. Keep the real session lock and
  # PAM authentication, then restore the prior compositor policy on exit.
  compositor() {
    @timeout@ --kill-after=@ipc_kill_after@ @ipc_timeout@ @hyprctl@ "$@"
  }
  read_policy() {
    compositor -i "$instance" -j getoption misc:allow_session_lock_restore |
      @jq@ -er '.bool | if type == "boolean" then tostring else error("Expected boolean restoration policy") end'
  }
  # The compositor selection expression is evaluated by jq.
  # shellcheck disable=SC2016
  instance="$(compositor -j instances | @jq@ -er --arg display "$WAYLAND_DISPLAY" '
    map(select(.wl_socket == $display)) |
    if length == 1 then .[0].instance else error("Expected one compositor for this display") end
  ')"
  : "${XDG_RUNTIME_DIR:?A private runtime directory is required}"
  umask 077
  recovery_key="$(printf '%s' "$instance" | @sha256sum@)"
  exec {recovery_fd}>"$XDG_RUNTIME_DIR/desktop-session-recovery-${recovery_key%% *}.lock"
  @flock@ "$recovery_fd"
  previous="$(read_policy)"
  manager_pid=
  # Invoked indirectly by the EXIT trap.
  # shellcheck disable=SC2329
  restore_policy() {
    trap '' HUP INT TERM
    local restore_status=0 restored=
    compositor -i "$instance" eval "hl.config({misc={allow_session_lock_restore=$previous}})" >/dev/null || restore_status=$?
    if ((restore_status == 0)); then
      restored="$(read_policy)" || restore_status=$?
      if [[ $restored != "$previous" ]]; then
        echo "Failed to restore the compositor session-lock policy" >&2
        restore_status=1
      fi
    fi
    if [[ -n $manager_pid ]]; then
      kill -TERM "$manager_pid" 2>/dev/null || true
      wait "$manager_pid" 2>/dev/null || true
    fi
    return "$restore_status"
  }
  trap restore_policy EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # An operator recovery may retry a locker that reached its start limit.
  # Clear only this display's failed unit, leaving other services untouched.
  if @timeout@ --kill-after=@ipc_kill_after@ @ipc_timeout@ @systemctl@ --user is-failed --quiet "$unit"; then
    @timeout@ --kill-after=@ipc_kill_after@ @ipc_timeout@ @systemctl@ --user reset-failed "$unit"
  fi
  compositor -i "$instance" eval 'hl.config({misc={allow_session_lock_restore=true}})' >/dev/null
  if [[ $(read_policy) != true ]]; then
    echo "The compositor did not enable session-lock recovery" >&2
    exit 1
  fi
  @systemctl@ --user start --wait "$unit" &
  manager_pid=$!
  status=0
  wait "$manager_pid" || status=$?
  manager_pid=
  exit "$status"
  ;;
running)
  exec @session_client@ "$@"
  ;;
*)
  echo "Expected lock, recover, or running" >&2
  exit 2
  ;;
esac
