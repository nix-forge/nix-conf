#!@bash@
# shellcheck shell=bash
set -euo pipefail

printf 'Database: '
@pgIsReady@ -h 127.0.0.1 -p @databasePort@
printf '\nAPI: '
@curl@ --fail --silent --show-error http://127.0.0.1:@apiPort@/api/health/ready
printf '\nDashboard: '
@curl@ --fail --silent --show-error --output /dev/null http://127.0.0.1:@webPort@/
printf 'ready\n\nListeners:\n'
@lsof@ -nP \
  -iTCP:@webPort@ -iTCP:@apiPort@ -iTCP:@proxyPort@ -iTCP:@databasePort@ \
  -sTCP:LISTEN || true
