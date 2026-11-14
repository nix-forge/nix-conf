# shellcheck shell=bash
# Nix supplies the command paths and check output.
# shellcheck disable=SC2154
set -euo pipefail
# Namespace root prepares only the synthetic fixture; the actual user-mode
# tmpfiles test runs as an ordinary user with no supplementary groups.
chmod 0711 "$TMPDIR"
fixture_directory="$TMPDIR/fixture-user"
mkdir -m 0700 "$fixture_directory"
chown 1000:1000 "$fixture_directory"
TMPDIR="$fixture_directory" HOME="$fixture_directory" \
  "$SETPRIV" --reuid 1000 --regid 1000 --clear-groups -- \
  "$PYTHON" "$CHECK" --rules "$RULES" --tmpfiles "$TMPFILES"
touch "$out"
