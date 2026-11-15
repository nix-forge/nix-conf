# shellcheck shell=bash
if [ "$(tty)" = /dev/tty1 ]; then
  exec sway
fi
