# shellcheck shell=bash
firewall=/usr/libexec/ApplicationFirewall/socketfilterfw

for app in \
  /usr/bin/ssh \
  /usr/bin/openssl \
  /usr/bin/python3 \
  /usr/bin/ruby \
  /usr/sbin/smbd; do
  if [ -e "$app" ]; then
    "$firewall" --blockapp "$app" >/dev/null 2>&1 || true
  fi
done

# Find this user's legacy Public directory by path, independent of the
# account's display name or the share's localized label.
public_directory=@lib_escapeShellArg_config_users_users_config_system_primaryU@
/usr/bin/dscl . -list /SharePoints 2>/dev/null |
  while IFS= read -r share_name; do
    share_path=$(/usr/bin/dscl . -read "/SharePoints/$share_name" directory_path 2>/dev/null) || continue
    share_path=$(printf '%s\n' "$share_path" | /usr/bin/sed 's/^directory_path: *//')
    if [ "$share_path" = "$public_directory" ]; then
      /usr/sbin/sharing -r "$share_name" >/dev/null 2>&1 || true
    fi
  done || true
