# shellcheck shell=bash
# Sourced by activation, which supplies newGenPath and nixProfileRemove.
(
  set -euo pipefail
  swap_preview_unit=${1:?unit path required}
  swap_preview_relative=${2:?generation-relative unit path required}
  if [[ -z ${newGenPath:-} || $swap_preview_relative == /* ||
    $swap_preview_relative == ../* || $swap_preview_relative == */../* ]]; then
    exit 0
  fi
  swap_preview_expected="$newGenPath/home-files/$swap_preview_relative"
  # Keep the root if managed-link installation failed or an unexpected link won.
  if [[ -L $swap_preview_unit && -f $swap_preview_unit &&
    -f $swap_preview_expected &&
    $(readlink -f -- "$swap_preview_unit") == "$(readlink -f -- "$swap_preview_expected")" ]]; then
    nixProfileRemove workstation-swap-preview
  fi
)
