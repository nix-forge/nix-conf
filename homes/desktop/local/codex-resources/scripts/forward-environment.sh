# shellcheck shell=bash
# Copy values inside systemd-run; only variable names appear in its argv.
forward_environment() {
  local entry name
  environment=()
  while IFS= read -r -d '' entry; do
    name=${entry%%=*}
    # systemd accepts ordinary environment names, not exported Bash functions.
    if [[ ! $name =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]]; then continue; fi
    case "$name" in
    INVOCATION_ID | JOURNAL_STREAM | SYSTEMD_EXEC_PID | NOTIFY_SOCKET | WATCHDOG_* | LISTEN_* | RUNTIME_DIRECTORY | STATE_DIRECTORY | CACHE_DIRECTORY | LOGS_DIRECTORY | CONFIGURATION_DIRECTORY | CREDENTIALS_DIRECTORY | CODEX_LAUNCH_UNIT) continue ;;
    esac
    environment+=("--setenv=$name")
  done < <(env -0)
}
