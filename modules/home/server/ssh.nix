{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  controlPathDir = "${config.home.homeDirectory}/.ssh/cm";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    extraOptionOverrides = {
      IgnoreUnknown = "UseKeychain";
    };

    settings = {
      "*.local" = {
        Compression = false;
        ConnectTimeout = "3";
      };

      "github.com gist.github.com gitlab.com codeberg.org" = {
        User = "git";
      };

      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "yes";
        Compression = false;

        ServerAliveInterval = 60;
        ServerAliveCountMax = 3;

        HashKnownHosts = true;

        ControlMaster = "auto";
        ControlPath = "${controlPathDir}/%C";
        ControlPersist = "10m";

        ConnectTimeout = "10";
        ConnectionAttempts = "2";
        TCPKeepAlive = "no";

        StrictHostKeyChecking = "accept-new";
        UpdateHostKeys = "yes";
      }
      // lib.optionalAttrs isDarwin { UseKeychain = "yes"; };
    };
  };

  home.activation.sshControlPathDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${controlPathDir}"
    chmod 700 "${controlPathDir}"
  '';
}
