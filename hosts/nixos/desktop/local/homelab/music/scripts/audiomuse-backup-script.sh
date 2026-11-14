# shellcheck shell=bash
set -eu
stamp="$(@pkgs_coreutils@/bin/date --utc +%Y%m%dT%H%M%SZ)"
partial=@lib_escapeShellArg_backupRoot_audiomuse@/audiomuse-$stamp.dump.partial
cleanup() {
  @pkgs_coreutils@/bin/rm -f "$partial"
}
trap cleanup EXIT
@config_services_postgresql_package@/bin/pg_dump \
  --host /run/postgresql --username audiomusedb --format custom \
  --file "$partial" audiomusedb
@pkgs_coreutils@/bin/mv "$partial" "${partial%.partial}"
trap - EXIT
@pkgs_findutils@/bin/find @lib_escapeShellArg_backupRoot_audiomuse@ \
  -type f -name 'audiomuse-*.dump' -mtime +14 -delete
