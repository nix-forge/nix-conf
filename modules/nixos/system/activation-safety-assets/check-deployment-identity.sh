# shellcheck shell=bash
identity_file=/run/current-system/etc/nixos/deployment-id
expected=@deploymentIdentity@
if [[ -e $identity_file || -L $identity_file ]]; then
  actual="$(<"$identity_file")"
  if [[ ! $actual =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ || $actual != "$expected" ]]; then
    echo 'refusing to omit or change the running deployment identity' >&2
    echo 'use the operational deployment flake; an intentional migration must explicitly disable the identity check' >&2
    exit 1
  fi
fi
