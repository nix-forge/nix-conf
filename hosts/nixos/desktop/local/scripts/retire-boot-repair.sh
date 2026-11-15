# shellcheck shell=bash
if [[ -L $1 && $(readlink -- "$1") == "$2/mkswap-swap-workstation.service" ]]; then
  rm -- "$1"
  rm -f -- "$2"
fi
