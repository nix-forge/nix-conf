#!@bash@
# shellcheck shell=bash
set -euo pipefail

if ! @privatePathGuard@ validate-directory @databaseDir@ 'Local database directory'; then
  exit 0
fi
if ! @databaseClusterValidator@ @databaseDir@; then
  printf 'Local database directory is incomplete, unsafe, or corrupt.\n' >&2
  exit 0
fi
if ! @privatePathGuard@ validate-directory @databaseSocketDir@ 'Local database socket directory'; then
  exit 0
fi
exec @secureFileSystem@ exec-cluster-socket \
  @databaseDir@ 18 @databaseSocketDir@ @postgres@ \
  -D . -h 127.0.0.1 -k __LOCAL_CONTROL_SOCKET_PATH__ -p @databasePort@
