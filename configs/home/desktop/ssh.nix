{ config, lib, ... }:
let
  includeCornell =
    if lib.hasAttrByPath [ "age" "secrets" "cornell-net-id-ssh-config" ] config then
      { Include = config.age.secrets.cornell-net-id-ssh-config.path; }
    else
      { };
in
{
  programs.ssh.matchBlocks = {
    # Servers
    "ugclinux" = {
      hostname = "ugclinux.cs.cornell.edu";

      extraOptions = {
        SetEnv = "TERM=xterm-256color";
      }
      // includeCornell;
    };

    # NERSC
    # https://docs.nersc.gov/connect/vscode/
    "dtn*.nersc.gov perlmutter*.nersc.gov *.nersc.gov" = {
      identitiesOnly = true;
      identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      extraOptions = {
        LogLevel = "QUIET";
        SetEnv = "TERM=xterm-256color";
      }
      // includeCornell;
    };
    "nid??????" = {
      hostname = "%h";
      identitiesOnly = true;
      identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      extraOptions = {
        LogLevel = "QUIET";
        StrictHostKeyChecking = "no";
        ProxyJump = "perlmutter.nersc.gov";
        SetEnv = "TERM=xterm-256color";
      }
      // includeCornell;
    };

    # Git
    "github.coecis.cornell.edu" = {
      hostname = "github.coecis.cornell.edu";
      user = "git";
      identitiesOnly = true;
      identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    };

    "gitlab.cs.cornell.edu" = {
      hostname = "gitlab.cs.cornell.edu";
      user = "git";
      identitiesOnly = true;
      identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    };
  };
}
