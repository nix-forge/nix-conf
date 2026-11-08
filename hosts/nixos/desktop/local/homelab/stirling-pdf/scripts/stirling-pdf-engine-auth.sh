# shellcheck shell=bash
umask 0027
target=@lib_escapeShellArg_engineAuthFile@
if test -s "$target"; then
  exit 0
fi
partial="$(mktemp "${target}.XXXXXX")"
trap 'rm -f "$partial"' EXIT
printf 'STIRLING_ENGINE_SHARED_SECRET=%s\n' "$(openssl rand -hex 32)" >"$partial"
chmod 0440 "$partial"
mv "$partial" "$target"
trap - EXIT
