{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  cmDir = "${config.home.homeDirectory}/.ssh/cm";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "*" = lib.mkMerge [
        {
          controlMaster = "auto";
          controlPersist = "10m";
          controlPath = "${cmDir}/%C";
          compression = true;

          hashKnownHosts = true;
          addKeysToAgent = "yes";
          forwardAgent = lib.mkForce false;
          serverAliveInterval = 60;
          serverAliveCountMax = 3;

          extraOptions = {
            UpdateHostKeys = "yes";
            StrictHostKeyChecking = "accept-new";
          };
        }

        (lib.optionalAttrs isDarwin {
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

      "*.local" = {
        compression = false;
      };
    };
  };

  home.activation.createSshControlMasterDir = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p ${cmDir}
    chmod 700 ${cmDir}
  '';
}
