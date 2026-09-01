#!@bash@
# shellcheck shell=bash
set -euo pipefail

url=@localUrl@
ssh_config="@colimaHome@/_lima/colima/ssh.config"
colima_bin=""
@curl@ -fsSI --max-time 2 "$url" >/dev/null 2>&1 && exit 0
for candidate in "$HOME/.nix-profile/bin/colima" "/etc/profiles/per-user/@username@/bin/colima" "/run/current-system/sw/bin/colima"; do
  [ -x "$candidate" ] && {
    colima_bin="$candidate"
    break
  }
done
[ -n "$colima_bin" ] || colima_bin="$(command -v colima || true)"
[ -f "$ssh_config" ] && [ -n "$colima_bin" ] || exit 0
for _ in $(@seq@ 1 12); do
  if "$colima_bin" ssh -- @curl@ -fsSI --max-time 2 @loopbackUrl@ >/dev/null 2>&1; then
    /usr/bin/ssh -F "$ssh_config" -O forward -L @forwardAddress@ -N -f lima-colima >/dev/null 2>&1 || true
    exit 0
  fi
  @sleep@ 2
done
