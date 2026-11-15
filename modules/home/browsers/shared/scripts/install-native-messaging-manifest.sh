# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
run @mkdir@ -p @lib_escapeShellArg_dirOf_target@
run @install@ -m 0600 @lib_escapeShellArg_source@ @lib_escapeShellArg_target@
