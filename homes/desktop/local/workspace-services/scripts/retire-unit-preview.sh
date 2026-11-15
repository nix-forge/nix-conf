#!/usr/bin/env bash
# Retire this scoped repair only after the managed generation links its units.
set -euo pipefail

config_home=$1
state_home=$2
preview="$config_home/systemd/user.control/workspace-edge.service"
target="$state_home/workspace-services/unit-preview/workspace-edge.service"
if [[ -L $preview && "$(readlink -- "$preview")" == "$target" ]]; then
  rm -- "$preview"
fi

for name in api worker dashboard edge; do
  override="$config_home/systemd/user/workspace-$name.service.d/90-runtime-recovery.conf"
  if [[ -f $override && ! -L $override ]] &&
    cmp -s -- "$override" <(printf '[Service]\nPrivateTmp=no\n'); then
    rm -- "$override"
  fi
done
