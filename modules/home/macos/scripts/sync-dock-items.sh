# shellcheck shell=bash
dock_cache_directory="@dockCacheDirectory@/home-manager-macos"
dock_mode=@lib_escapeShellArg_cfg_mode@
dock_config_hash_path="$dock_cache_directory/dock-config.hash"
dock_state_hash_path="$dock_cache_directory/dock-state.hash"
old_config_hash=$(cat "$dock_config_hash_path" 2>/dev/null || true)
old_state_hash=$(cat "$dock_state_hash_path" 2>/dev/null || true)
new_config_hash="@dockStateHash@"
current_state_hash=""
needs_sync=""

if [ "$dock_mode" = authoritative ] && [ -z "${DRY_RUN:-}" ]; then
  current_state_hash="$(@dockStateExe@)" || exit 1
fi

if [ "$old_config_hash" != "$new_config_hash" ]; then
  needs_sync=1
elif [ "$dock_mode" = authoritative ] && [ "$old_state_hash" != "$current_state_hash" ]; then
  needs_sync=1
fi

if [ -n "$needs_sync" ] || [ -n "${DRY_RUN:-}" ]; then
  verboseEcho "setting up Dock items..."

  if [ -z "${DRY_RUN:-}" ] && ! @dockutilExe@ --list >/dev/null; then
    echo "error: dockutil cannot read this macOS Dock; refusing to remove any items" >&2
    exit 1
  fi

  @validateTargets@
  @renderCommandFns_commandFns@

  if [ -z "${DRY_RUN:-}" ]; then
    current_state_hash="$(@dockStateExe@)" || exit 1
    install -d -m 0700 "$dock_cache_directory"
    printf '%s\n' "$new_config_hash" >"$dock_config_hash_path.new"
    printf '%s\n' "$current_state_hash" >"$dock_state_hash_path.new"
    chmod 0600 "$dock_config_hash_path.new" "$dock_state_hash_path.new"
    mv -f "$dock_config_hash_path.new" "$dock_config_hash_path"
    mv -f "$dock_state_hash_path.new" "$dock_state_hash_path"
  fi
else
  verboseEcho "Dock items unchanged, skipping..."
fi
