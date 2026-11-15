# shellcheck shell=bash
umask 077
test "$(findmnt -rn -o SOURCE --target /srv/actual)" = /dev/mapper/actual-vault || {
  echo "Actual encrypted storage is unavailable" >&2
  exit 1
}
runtime=/run/nix-seal/actual-cli
export ACTUAL_SERVER_URL=@lib_escapeShellArg_actualOrigin@
export ACTUAL_IDENTITY_URL=@lib_escapeShellArg_identityOrigin@
install -d -m 0700 "$runtime"
exec 9>"$runtime/login.lock"
flock 9
if [ ! -s "$runtime/session-token" ] || [ -n "$(find "$runtime/session-token" -mmin +1380 -print)" ]; then
  python3 @scripts_actual_cli_login_py@ \
    "$runtime/username" "$runtime/password" "$runtime/session-token"
fi
flock -u 9
export ACTUAL_SESSION_TOKEN_FILE="$runtime/session-token"
export ACTUAL_DATA_DIR=/srv/actual/cli
exec @actualCli@/bin/actual-cli "$@"
