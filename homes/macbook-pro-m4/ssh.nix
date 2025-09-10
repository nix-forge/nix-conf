{ config, ... }:
{
  programs.ssh.matchBlocks = {
    # Servers
    "ugclinux" = {
      hostname = "ugclinux.cs.cornell.edu";

      extraOptions = {
        Include = config.age.secrets.cornell-net-id-ssh-config.path;
        SetEnv = "TERM=xterm-256color";
      };
    };
    "perlmutter" = {
      hostname = "perlmutter.nersc.gov";

      extraOptions = {
        Include = config.age.secrets.cornell-net-id-ssh-config.path;
        SetEnv = "TERM=xterm-256color";
      };
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
