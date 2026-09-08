{ config, lib, ... }: {
  # The application firewall remains permissive for signed Apple services so
  # HomeKit, AirPlay, and Continuity continue to work.  Explicit blocks below
  # prevent general-purpose command-line tools from becoming LAN listeners.
  networking.applicationFirewall = {
    enable = true;
    blockAllIncoming = false;
    allowSignedApp = false;
    allowSigned = true;
    enableStealthMode = true;
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
    firewall=/usr/libexec/ApplicationFirewall/socketfilterfw

    for app in \
      /usr/bin/ssh \
      /usr/bin/openssl \
      /usr/bin/python3 \
      /usr/bin/ruby \
      /usr/sbin/smbd
    do
      if [ -e "$app" ]; then
        "$firewall" --blockapp "$app" >/dev/null 2>&1 || true
      fi
    done

    # Find this user's legacy Public directory by path, independent of the
    # account's display name or the share's localized label.
    public_directory=${lib.escapeShellArg "${config.users.users.${config.system.primaryUser}.home}/Public"}
    /usr/bin/dscl . -list /SharePoints 2>/dev/null |
      while IFS= read -r share_name; do
        share_path=$(/usr/bin/dscl . -read "/SharePoints/$share_name" directory_path 2>/dev/null) || continue
        share_path=$(printf '%s\n' "$share_path" | /usr/bin/sed 's/^directory_path: *//')
        if [ "$share_path" = "$public_directory" ]; then
          /usr/sbin/sharing -r "$share_name" >/dev/null 2>&1 || true
        fi
      done || true
  '';
}
