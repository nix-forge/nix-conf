# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
test -d @commandTree@
printf '%s' 'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==' | base64 -d >"source image.gif"
PATH=/nonexistent @lib_getExe_importer@ "$PWD/source image.gif"
cmp "source image.gif" @lib_escapeShellArg_literalPath_source_image_gif@
test "$(stat -c %a @lib_escapeShellArg_literalPath@)" = 700
test "$(stat -c %a @lib_escapeShellArg_literalPath_source_image_gif@)" = 600
status=0
PATH=/nonexistent @lib_getExe_importer@ || status=$?
test "$status" = 64
export XDG_CONFIG_HOME="$TMPDIR/wallpaper-config"
mkdir -p @configuredPolicyDirectory@
ln -s @rotating_config_xdg_configFile_desktop_wallpaper_policy_comm@ @configuredPolicyDirectory@/policy-command
@lib_getExe_settings@ plan >plan.json
jq -e 'all(.[]; .category != "cityscapes")' plan.json
jq -e '[.[] | select(.connection == "esaHubble") | .subcategory] == ["nebulae"]' plan.json
@lib_getExe_settings@ source esaHubble space/galaxies on >/dev/null 2>&1
@lib_getExe_settings@ plan esaHubble >plan.json
jq -e '[.[].subcategory] | sort == ["galaxies", "nebulae"]' plan.json
@lib_getExe_settings@ connection esaHubble off >/dev/null 2>&1
test "$(@lib_getExe_settings@ plan esaHubble)" = '[]'
touch "$out"
