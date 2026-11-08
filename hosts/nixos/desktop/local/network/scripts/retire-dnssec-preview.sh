# shellcheck shell=bash
if [[ -L $1 && $(readlink -- "$1") == "$2" ]]; then
  rm -- "$1"
  rm -f -- "$2"
fi
