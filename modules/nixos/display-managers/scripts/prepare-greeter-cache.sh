# shellcheck shell=bash
@pkgs_coreutils@/bin/install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet
# Repair ownership after numeric UID changes without following symlinks.
# Read and rewrite the user-writable cache only as the greeter account.
for cache in /var/cache/tuigreet/last*; do
  if [[ -e $cache || -L $cache ]]; then
    @pkgs_coreutils@/bin/chown --no-dereference greeter:greeter -- "$cache"
  fi
done
@pkgs_util_linux@/bin/runuser -u greeter -- @lib_escapeShellArgs_lib_getExe_prepareCache_var_cache_tuigre@
