# shellcheck shell=bash
receipt=@lib_escapeShellArg_cfg_stateDirectory_bootstrap_profile_json@
profile=@lib_escapeShellArg_config_home_homeDirectory_nix_profile@
if test -f "$receipt"; then
  manifest=$(nix profile list --profile "$profile" --json)
  if test "$(jq -r --slurpfile receipt "$receipt" \
    '(.elements[$receipt[0].name].storePaths // []) == [$receipt[0].storePath]' \
    <<<"$manifest")" = true; then
    element=$(jq -r '.name' "$receipt")
    nix profile remove --profile "$profile" "$element"
  fi
  rm -f -- "$receipt"
fi
