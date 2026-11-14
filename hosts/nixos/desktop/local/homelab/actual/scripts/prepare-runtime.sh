# shellcheck shell=bash
test "$(@pkgs_util_linux@/bin/findmnt -rn -o SOURCE --target @mount@)" = /dev/mapper/@mapper@
chmod 0711 @mount@
install -d -m 0700 -o actual -g actual @mount@/server
install -d -m 0700 -o ianmh -g users @mount@/cli /run/nix-seal/actual-cli
install -m 0400 -o ianmh -g users "$CREDENTIALS_DIRECTORY/username" /run/nix-seal/actual-cli/username
install -m 0400 -o ianmh -g users "$CREDENTIALS_DIRECTORY/password" /run/nix-seal/actual-cli/password
