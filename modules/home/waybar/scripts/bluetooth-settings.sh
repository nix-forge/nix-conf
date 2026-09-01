#!@bash@
# shellcheck shell=bash
set -eux
export PATH="@runtimePath@:$PATH"
is_powered_on="$(
  bluetoothctl show |
    awk '/Name: '"$(hostname)"'$/{p=1} p && /Powered: yes/{print "true"; exit} END{if(!NR || !p) print "false"}'
)"
if [[ $is_powered_on == 'true' ]]; then
  blueman-manager
else
  rfkill unblock bluetooth && sleep 1 || true
  bluetoothctl power on
  sleep 0.5
  blueman-manager
fi
