# shellcheck shell=bash
test "$(@pkgs_util_linux@/bin/findmnt -rn -o SOURCE --target @mount@)" = /dev/mapper/@mapper@
test -d @mount@/server
