#!@bash@
# shellcheck shell=bash
set -euo pipefail

# The reverse forward is useful only after the loopback mTLS listener exists.
# Waiting here avoids a restart storm while VMware recreates its networks and
# lets launchd keep one stable owner for the tunnel.
retry_delay=5
while ! @netcat@ -4 -z -w 1 127.0.0.1 @proxyPort@ >/dev/null 2>&1; do
  printf 'Waiting for local control proxy on 127.0.0.1:%s before starting the dev-vm tunnel.\n' \
    @proxyPort@ >&2
  @sleep@ "$retry_delay"
  if [ "$retry_delay" -lt 30 ]; then
    retry_delay=$((retry_delay + 5))
  fi
done

exec @ssh@ \
  -F @sshConfig@ \
  -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3 \
  -R 127.0.0.1:@proxyPort@:127.0.0.1:@proxyPort@ \
  dev-vm
