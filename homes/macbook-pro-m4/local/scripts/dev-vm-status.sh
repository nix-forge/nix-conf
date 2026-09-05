#!@bash@
# shellcheck shell=bash
set -euo pipefail

vm_host="$(@devVmHost@ \
  --require-route-source @hostOnlySourceAddress@ \
  --route-port @sshPort@)"

printf 'Host-only VM address: %s\n' "$vm_host"
@netcat@ -4 -s @hostOnlySourceAddress@ -vz -w 3 "$vm_host" @sshPort@

printf '\nMac control-host listeners:\n'
@lsof@ -nP -iTCP:5173 -iTCP:8788 -iTCP:8443 -sTCP:LISTEN || true

printf '\nWindows development prerequisites:\n'
ssh_arguments=()
if [ -n "${DEV_VM_SSH_CONFIG:-}" ]; then
  ssh_arguments=(-F "$DEV_VM_SSH_CONFIG")
fi
# The single-quoted script is deliberately expanded by the remote shell.
# shellcheck disable=SC2016
@ssh@ "${ssh_arguments[@]}" dev-vm '
  set -eu
  for command_name in codex git dotnet pwsh; do
    command -v "$command_name" >/dev/null || {
      printf "Missing required command: %s\n" "$command_name" >&2
      exit 1
    }
    printf "%s: %s\n" "$command_name" "$(command -v "$command_name")"
  done
'
