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

    matchBlocks = {
      local = {
        host = "*.local";
        compression = false;
        extraOptions = {
          ConnectTimeout = "3";
        };
      };

      gitForges = {
        host = "github.com gist.github.com gitlab.com codeberg.org";
        user = "git";
      };

      "*" = {
        forwardAgent = false;
        addKeysToAgent = "yes";
        compression = false;

        serverAliveInterval = 60;
        serverAliveCountMax = 3;

        hashKnownHosts = true;

        controlMaster = "auto";
        controlPath = "${controlPathDir}/%C";
        controlPersist = "10m";

        extraOptions = {
          ConnectTimeout = "10";
          ConnectionAttempts = "2";
          TCPKeepAlive = "no";

          StrictHostKeyChecking = "accept-new";
          UpdateHostKeys = "yes";
        }
        // lib.optionalAttrs isDarwin { UseKeychain = "yes"; };
      };
    };
  };

  home.activation.sshControlPathDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${controlPathDir}"
    chmod 700 "${controlPathDir}"
  '';
}
