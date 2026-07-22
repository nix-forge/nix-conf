{ config, lib, ... }:
let
  includeCornell =
    if lib.hasAttrByPath [ "age" "secrets" "cornell-net-id-ssh-config" ] config then
      { Include = config.age.secrets.cornell-net-id-ssh-config.path; }
    else
      { };
in
{
  programs.ssh.settings = {
    # Servers
    "ugclinux" = {
      HostName = "ugclinux.cs.cornell.edu";

      SetEnv = {
        TERM = "xterm-256color";
      };
    }
    // includeCornell;

    # NERSC
    # https://docs.nersc.gov/connect/vscode/
    "dtn*.nersc.gov perlmutter*.nersc.gov *.nersc.gov" = {
      IdentitiesOnly = true;
      IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      LogLevel = "QUIET";
      SetEnv = {
        TERM = "xterm-256color";
      };
    }
    // includeCornell;
    "nid??????" = {
      HostName = "%h";
      IdentitiesOnly = true;
      IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      LogLevel = "QUIET";
      StrictHostKeyChecking = "no";
      ProxyJump = "perlmutter.nersc.gov";
      SetEnv = {
        TERM = "xterm-256color";
      };
    }
    // includeCornell;

    # Git
    "github.coecis.cornell.edu" = {
      HostName = "github.coecis.cornell.edu";
      User = "git";
      IdentitiesOnly = true;
      IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    };

    "gitlab.cs.cornell.edu" = {
      HostName = "gitlab.cs.cornell.edu";
      User = "git";
      IdentitiesOnly = true;
      IdentityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    };
  };
}
