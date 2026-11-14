# shellcheck shell=bash
printf '%s\n' 'NIX_FORGE_LIBGIT2_FULL_UTIL_BEGIN util_tests -v -v'
status=0
./util_tests -v -v || status=$?
printf 'NIX_FORGE_LIBGIT2_FULL_UTIL_END status=%s\n' "$status"
test "$status" -eq 0
