# shellcheck shell=bash
set -euo pipefail
# systemd-inhibit invokes this only after logind grants the inhibitor.
@getExe_pkgs_systemd_systemd_notify@ --ready
exec @getExe_pkgs_coreutils_sleep@ infinity
