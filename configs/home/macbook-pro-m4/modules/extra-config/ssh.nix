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
    cornellGit = {
      host = "github.coecis.cornell.edu gitlab.cs.cornell.edu";
      user = "git";
      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };

    ugclinux = {
      host = "ugclinux";
      hostname = "ugclinux.cs.cornell.edu";
      setEnv = {
        TERM = "xterm-256color";
      };

      extraOptions = { } // includeCornell;
    };

    nerscLogin = {
      host = "dtn*.nersc.gov perlmutter*.nersc.gov *.nersc.gov";
      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      setEnv = {
        TERM = "xterm-256color";
      };

      extraOptions = {
        LogLevel = "QUIET";
      }
      // includeCornell;
    };

    perlmutterAgent = {
      host = "perlmutter-agent";
      hostname = "perlmutter.nersc.gov";
      user = null;
      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      forwardAgent = true;

      setEnv = {
        TERM = "xterm-256color";
      };
      extraOptions = {
        LogLevel = "QUIET";
      }
      // includeCornell;
    };

    nerscCompute = {
      host = "nid??????";
      hostname = "%h";
      proxyJump = "perlmutter.nersc.gov";

      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      setEnv = {
        TERM = "xterm-256color";
      };

      userKnownHostsFile = "${config.home.homeDirectory}/.ssh/known_hosts_nersc_compute";

      extraOptions = {
        LogLevel = "QUIET";
        StrictHostKeyChecking = "accept-new";

        UpdateHostKeys = "no";
      }
      // includeCornell;
    };

    gitForges = {
      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };
}
