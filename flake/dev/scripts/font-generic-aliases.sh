# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
grep -F -- @lib_escapeShellArg_syntheticSans@ @syntheticRules_cssGenericAlias@ >/dev/null
grep -F -- @lib_escapeShellArg_syntheticSerif@ @syntheticRules_cssGenericAlias@ >/dev/null
grep -F -- @lib_escapeShellArg_syntheticMonospace@ @syntheticRules_cssGenericAlias@ >/dev/null
! grep -F -- '@sansSerifFamily@' @syntheticRules_cssGenericAlias@ >/dev/null
! grep -F -- '@serifFamily@' @syntheticRules_cssGenericAlias@ >/dev/null
! grep -F -- '@monospaceFamily@' @syntheticRules_cssGenericAlias@ >/dev/null
touch "$out"
