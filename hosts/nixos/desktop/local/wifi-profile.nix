{
  config,
  lib,
  pkgs,
  ...
}:
{
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
      source = ./iwd-trusted.psk.template;
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

  # IWD owns and may augment its state file (for example, with SAE caches), so
  # materialize a fresh credential-backed base profile before it starts rather
  # than linking the mutable state directory into /run. The sealed first line
  # supplies the IWD filename at activation time, keeping the SSID out of the
  # Nix store and repository. This is a soft dependency: if secret activation
  # ever fails, IWD can still use the last known-good profile and preserve
  # remote recovery access.
  systemd.services.iwd-trusted-profile = {
    description = "Materialize the sealed IWD profile";
    unitConfig.ConditionPathExists = config.nixSeal.templates."iwd-trusted-profile".path;
    wantedBy = [ "iwd.service" ];
    wants = [ "nix-seal-activate.service" ];
    after = [ "nix-seal-activate.service" ];
    before = [ "iwd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
    };
    serviceConfig.ExecStart = pkgs.replaceVarsWith {
      name = "materialize-iwd-trusted-profile";
      src = ./scripts/materialize-iwd-trusted-profile.sh;
      isExecutable = true;
      replacements = {
        bash = "${pkgs.bash}/bin/bash";
        install = "${pkgs.coreutils}/bin/install";
        sed = "${pkgs.gnused}/bin/sed";
        mktemp = "${pkgs.coreutils}/bin/mktemp";
        rm = "${pkgs.coreutils}/bin/rm";
        tail = "${pkgs.coreutils}/bin/tail";
        chmod = "${pkgs.coreutils}/bin/chmod";
        cmp = "${pkgs.diffutils}/bin/cmp";
        mv = "${pkgs.coreutils}/bin/mv";
        templatePath = lib.escapeShellArg config.nixSeal.templates."iwd-trusted-profile".path;
      };
    };
  };
}
