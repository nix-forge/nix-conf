# shellcheck shell=bash
if ! @lib_getExe_pkgs_jq@ -e 'any(.pcrValues[]?; .pcr == 4)' /var/lib/systemd/pcrlock.json >/dev/null; then
  echo 'systemd-pcrlock generated a policy without PCR 4' >&2
  exit 1
fi
