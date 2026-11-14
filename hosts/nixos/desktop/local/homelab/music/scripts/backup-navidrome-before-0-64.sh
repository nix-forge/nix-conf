# shellcheck shell=bash
set -eu
database=/var/lib/navidrome/navidrome.db
backup=@lib_escapeShellArg_backupRoot_navidrome_pre_0_64_0_db@
if [ -f "$database" ] && [ ! -e "$backup" ]; then
  partial="$backup.partial"
  trap '@pkgs_coreutils@/bin/rm -f "$partial"' EXIT
  @pkgs_sqlite@/bin/sqlite3 "$database" ".backup '$partial'"
  @pkgs_coreutils@/bin/mv "$partial" "$backup"
  trap - EXIT
fi
