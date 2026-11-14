# shellcheck shell=bash
# shellcheck disable=SC2154
set -euo pipefail
export COPILOT=1 TERM_PROGRAM=vscode
export EDITOR_CALLS="$PWD/editor-calls"
export SHELL_INTEGRATION_FILE="$PWD/integration 'quoted' %literal\$dollar.sh"
printf '%s\n' 'export EDITOR_INTEGRATION=1' >"$SHELL_INTEGRATION_FILE"

# Null package retains the prompt without guessing an external executable.
bash -eu -c '
  source "$nullHook"
  [[ $PS1 == "copilot:\w\\\$ " ]]
  [[ ${EDITOR_INTEGRATION:-} == "" && ${DIRENV_FIXTURE:-} == "" ]]
  [[ ! -e $EDITOR_CALLS ]]
'

# Disabling the editor must not retain its executable as an optional dependency.
bash -eu -c '
  source "$disabledHook"
  [[ $PS1 == "copilot:\w\\\$ " ]]
  [[ ${EDITOR_INTEGRATION:-} == "" && ${DIRENV_FIXTURE:-} == "" ]]
  [[ ! -e $EDITOR_CALLS ]]
'

# Selected packages own both editor lookup and generated direnv initialization.
bash -eu -c '
  source "$selectedHook"
  [[ $EDITOR_INTEGRATION == 1 && $DIRENV_FIXTURE == 1 ]]
  [[ -s $EDITOR_CALLS ]]
'

# An unavailable optional integration cannot abort an errexit shell.
export LOOKUP_FAIL=true
bash -eu -c '
  source "$optionalHook"
  [[ $PS1 == "copilot:\w\\\$ " ]]
  [[ ${EDITOR_INTEGRATION:-} == "" && ${DIRENV_FIXTURE:-} == "" ]]
  [[ ! -v __vscode_executable && ! -v __vscode_shell_integration ]]
'

unset COPILOT TERM_PROGRAM
bash -eu -c 'source "$optionalHook"; [[ ! -v __vscode_executable ]]'
