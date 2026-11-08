# shellcheck shell=bash
umask 077
mkdir -p @lib_escapeShellArg_cfg_stateDirectory@
report_file=$(mktemp @lib_escapeShellArg_cfg_stateDirectory_report_XXXXXXXX@)
trap 'rm -f -- "$report_file"' EXIT
dev-worktree doctor >"$report_file"
mv -- "$report_file" @lib_escapeShellArg_cfg_stateDirectory_inventory_json@
