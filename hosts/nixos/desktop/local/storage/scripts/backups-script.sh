# shellcheck shell=bash
set -eu
@guard_name@
restic check --read-data
@stamp_name_integrity@
@python@ @helper@ @helperConfig@ restore @lib_escapeShellArg_name@
@stamp_name_restore@
