{ config, ... }:
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

      extraOptions = {
        Include = config.age.secrets.cornell-net-id-ssh-config.path;
      };
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
        Include = config.age.secrets.cornell-net-id-ssh-config.path;
      };
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
        Include = config.age.secrets.cornell-net-id-ssh-config.path;
      };
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
        Include = config.age.secrets.cornell-net-id-ssh-config.path;

        StrictHostKeyChecking = "accept-new";

        UpdateHostKeys = "no";
      };
    };

    gitForges = {
      identitiesOnly = true;
      identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };
}
