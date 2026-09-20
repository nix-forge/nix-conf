#!@bash@
# shellcheck shell=bash
set -euo pipefail

environment_state="$(@secureFileSystem@ inspect-generation-file @environmentFile@ 600)" || {
  printf 'Control-plane environment is unsafe; private proxy remains stopped.\n' >&2
  exit 0
}
if [ "$environment_state" = missing ]; then
  printf 'Control-plane environment is absent; private proxy remains stopped.\n' >&2
  exit 0
fi

# VMware can recreate the host-only interface after this launchd job starts.
# Caddy correctly refuses a missing bind address, but allowing that transient
# failure to terminate this process leaves launchd's throttle policy in charge
# of recovery. Keep the owner alive and retry with bounded backoff instead.
retry_delay=5
caddy_pid=''
stop_requested=0

stop_proxy() {
  stop_requested=1
  if [ -n "$caddy_pid" ]; then
    kill -TERM "$caddy_pid" 2>/dev/null || true
  fi
}
trap stop_proxy TERM INT

while :; do
  @secureFileSystem@ exec-proxy @pkiDir@ @environmentFile@ @caddy@ \
    run --config @proxyConfig@ --adapter caddyfile &
  caddy_pid=$!
  if wait "$caddy_pid"; then
    caddy_status=0
  else
    caddy_status=$?
  fi
  caddy_pid=''

  if [ "$stop_requested" -eq 1 ] || [ "$caddy_status" -eq 0 ]; then
    exit 0
  fi

  printf 'Local control proxy exited with status %s; retrying in %s seconds.\n' \
    "$caddy_status" "$retry_delay" >&2
  @sleep@ "$retry_delay" &
  sleep_pid=$!
  wait "$sleep_pid" || true
  if [ "$stop_requested" -eq 1 ]; then
    exit 0
  fi
  if [ "$retry_delay" -lt 60 ]; then
    retry_delay=$((retry_delay * 2))
  fi
done
