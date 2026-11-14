# shellcheck shell=bash
if [[ $# -ge 2 ]]; then
  echo "Browser collection isolation uses Linux Fontconfig. On macOS, run tests/fonts/check_coretext.swift after activation." >&2
  exit 2
fi
