#!/usr/bin/env bash

set -euo pipefail

readonly PORT='@port@'
readonly HEALTH_URL="http://127.0.0.1:${PORT}/v2/languages"
readonly STATE_DIR='@stateDir@'

'@settingsPatcherExe@'
'@mkdirExe@' -p "${STATE_DIR}"

if ! '@curlExe@' -fsS --max-time 1 "${HEALTH_URL}" >/dev/null 2>&1; then
  '@languageToolExe@' --config '@languageToolConfig@' --port "${PORT}" \
    >"${STATE_DIR}/languagetool.log" 2>&1 &
  language_tool_pid=$!

  ready=false
  for _ in $('@seqExe@' 1 60); do
    if '@curlExe@' -fsS --max-time 1 "${HEALTH_URL}" >/dev/null 2>&1; then
      ready=true
      break
    fi
    if ! kill -0 "${language_tool_pid}" 2>/dev/null; then
      break
    fi
    '@sleepExe@' 1
  done

  if [ "${ready}" != true ]; then
    printf '%s\n' "LanguageTool failed to start; see ${STATE_DIR}/languagetool.log" >&2
    exit 1
  fi
fi

exec '@libreofficeExe@' "$@"
