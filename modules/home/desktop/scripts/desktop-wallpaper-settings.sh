# shellcheck shell=bash
# The configured, shell-quoted path can contain literal dollar signs.
# shellcheck disable=SC2016
exec @policyCommand@ "$@"
