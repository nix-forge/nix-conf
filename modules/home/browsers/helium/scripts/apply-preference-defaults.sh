#!@bash@
# shellcheck shell=bash
@defaults@ @defaultsFile@ @preferencesPath@ || printf '%s\n' 'Could not apply Helium preference defaults.' >&2
