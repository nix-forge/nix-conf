#!/usr/bin/env bash

set -euo pipefail

readonly PROFILE='@profile@'

if '@pgrepExe@' -f '(^|/)soffice(\.bin)?( |$)' >/dev/null 2>&1; then
  printf '%s\n' "LibreOffice is running; settings were not changed. Quit LibreOffice, then run libreoffice-apply-settings." >&2
  exit 0
fi

exec '@pythonExe@' '@settingsPatcherPython@' "${PROFILE}" '@settingsJson@'
