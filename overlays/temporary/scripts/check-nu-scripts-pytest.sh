# shellcheck shell=bash
# The install hook supplies the actual package output path.
# Nushell resolves $env; Bash passes the expression unchanged.
# shellcheck disable=SC2154,SC2016
NU_CHECK_FILE="$out/share/nu_scripts/custom-completions/pytest/pytest-completions.nu" \
  @nu@ --no-config-file --commands 'if not (nu-check --debug $env.NU_CHECK_FILE) { exit 1 }'
