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
    "github.coecis.cornell.edu gitlab.cs.cornell.edu" = {
      User = "git";
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };

    ugclinux = {
      HostName = "ugclinux.cs.cornell.edu";
      SetEnv = {
        TERM = "xterm-256color";
      };

    }
    // includeCornell;

    "dtn*.nersc.gov perlmutter*.nersc.gov *.nersc.gov" = {
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      SetEnv = {
        TERM = "xterm-256color";
      };

      LogLevel = "QUIET";
    }
    // includeCornell;

    "perlmutter-agent" = {
      HostName = "perlmutter.nersc.gov";
      User = null;
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      ForwardAgent = true;

      SetEnv = {
        TERM = "xterm-256color";
      };
      LogLevel = "QUIET";
    }
    // includeCornell;

    "nid??????" = {
      HostName = "%h";
      ProxyJump = "perlmutter.nersc.gov";

      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      SetEnv = {
        TERM = "xterm-256color";
      };

      UserKnownHostsFile = "${config.home.homeDirectory}/.ssh/known_hosts_nersc_compute";

      LogLevel = "QUIET";
      StrictHostKeyChecking = "accept-new";

      UpdateHostKeys = "no";
    }
    // includeCornell;

    "github.com gist.github.com gitlab.com codeberg.org" = {
      IdentitiesOnly = true;
      IdentityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };
}
