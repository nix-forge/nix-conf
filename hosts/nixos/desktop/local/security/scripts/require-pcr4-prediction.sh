# shellcheck shell=bash
prediction="$(@pkgs_systemd@/lib/systemd/systemd-pcrlock predict --json=short --components=/etc/pcrlock.d --components=/var/lib/pcrlock.d --location=770 --pcr=4)" || exit 1
if ! @lib_getExe_pkgs_jq@ -e 'type == "object" and length > 0' <<<"$prediction" >/dev/null; then
  echo 'systemd-pcrlock cannot predict PCR 4; refusing to replace the policy' >&2
  exit 1
fi
