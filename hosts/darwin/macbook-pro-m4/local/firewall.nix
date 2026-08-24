{ lib, ... }: {
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

    # This legacy public SMB share was writable by guests. It is not needed
    # for HomeKit/AirPlay and must not be recreated by later activations.
    /usr/sbin/sharing -r "Ian Holloway’s Public Folder" >/dev/null 2>&1 || true
  '';
}
