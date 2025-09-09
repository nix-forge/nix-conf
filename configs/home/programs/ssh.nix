{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv) isDarwin;
  cmDir = "${config.home.homeDirectory}/.ssh/cm"; # short path for mux sockets
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "*" = lib.mkMerge [
        {
          # Fast, reliable connections
          controlMaster = "auto";
          controlPersist = "10m";
          controlPath = "${cmDir}/%C"; # hashed path avoids 'too long' errors
          compression = true; # good on slow/latency links

          # Safety + convenience
          hashKnownHosts = true;
          addKeysToAgent = "yes";
          forwardAgent = lib.mkForce false; # only enable per-host when needed
          serverAliveInterval = 60;
          serverAliveCountMax = 3;

          # safer first-connection behavior + key rotation
          extraOptions = {
            UpdateHostKeys = "yes";
            StrictHostKeyChecking = "accept-new";
          };
        }

        (lib.optionalAttrs isDarwin {
          # macOS: Use the system keychain for private keys
          extraOptions = {
            "IgnoreUnknown" = "UseKeychain";
            "UseKeychain" = "yes";
          };
        })
      ];

      "github.com" = {
        hostname = "github.com";
        user = "git";
      };

      "gist.github.com" = {
        hostname = "gist.github.com";
        user = "git";
      };

      "gitlab.com" = {
        hostname = "gitlab.com";
        user = "git";
      };

      "codeberg.org" = {
        user = "git";
        hostname = "codeberg.org";
      };

      # Local network: don’t waste CPU compressing
      "*.local" = {
        compression = false;
      };
    };
  };

  # create the control master directory if it doesn't exist
  home.activation.createSshControlMasterDir = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p ${cmDir}
    chmod 700 ${cmDir}
  '';
}
