# shellcheck shell=bash
echo >&2 "reconciling inactive macOS user defaults..."
@lib_concatMapStringsSep_n_entry_deleteUserDefault_builtins_e@
