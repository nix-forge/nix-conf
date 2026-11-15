# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
cmp @plugin@ @modules_home_mpv_mpv_anime_toggle_lua@
test ! -x @plugin@
test -f @luaParseOnly@
@lua_interpreter@ @lua_check_mpv_anime_toggle_lua@ @plugin@
touch "$out"
