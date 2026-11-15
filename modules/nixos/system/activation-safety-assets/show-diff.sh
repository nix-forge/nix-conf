# shellcheck shell=bash
incoming="${1-}"
if [[ -e /run/current-system && -n $incoming ]]; then
  echo "--- diff to current system"
  PATH="$incoming/sw/bin:$PATH" @pkgs_nvd@/bin/nvd diff /run/current-system "$incoming"
  echo "---"
fi
