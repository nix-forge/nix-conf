# shellcheck shell=bash
# Run under interactive Bash because the real integration intentionally skips scripts.
# shellcheck disable=SC1090
source "$GHOSTTY_CHECK_SOURCE"
set -e
trap - DEBUG
PROMPT_COMMAND=()
_ghostty_executing=0
_ghostty_last_reported_cwd=$PWD
BLE_VERSION=diagnostic
with_ble=$(__ghostty_precmd 0)
[[ "$with_ble" == *$'\e]133;P;k=i\a'* ]]
[[ "$with_ble" != *$'\e]133;A;'* ]]
unset BLE_VERSION
without_ble=$(__ghostty_precmd 0)
[[ "$without_ble" == *$'\e]133;A;'* ]]
