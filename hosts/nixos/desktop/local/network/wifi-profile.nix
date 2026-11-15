{ config, ... }: {
  assertions = [
    {
      assertion = config.networking.wireless.iwd.enable;
      message = "The sealed IWD profile requires networking.wireless.iwd.enable.";
    }
    {
      assertion = !config.networking.wireless.iwd.settings.General.EnableNetworkConfiguration;
      message = "The sealed IWD profile expects systemd-networkd, not IWD, to own IP configuration.";
    }
  ];

  # The credential never enters the Nix store.  nix-seal renders the complete
  # IWD profile only at activation into its no-swap runtime directory.
  nixSeal = {
    secrets."wifi-trusted-ssid" = {
      owner = "root";
      group = "root";
      mode = "0400";
    };

    secrets."wifi-trusted-passphrase" = {
      owner = "root";
      group = "root";
      mode = "0400";
    };

    templates."iwd-trusted-profile" = {
      # Keep connection behavior visible beside the secret bindings.
      content = ''
        SSID={{nix-seal:ssid}}
        [Security]
        Passphrase={{nix-seal:passphrase}}

        [Settings]
        AutoConnect=true
        Hidden=false
      '';
      placeholders.passphrase = {
        secret = "wifi-trusted-passphrase";
        encoding = "utf8";
      };
      placeholders.ssid = {
        secret = "wifi-trusted-ssid";
        encoding = "utf8";
      };
      owner = "root";
      group = "root";
      mode = "0600";
    };
  };

  networking.wireless.iwd.runtimeProfiles.trusted = {
    source = config.nixSeal.templates.iwd-trusted-profile.path;
    afterUnits = [ "nix-seal-activate.service" ];
  };
}
