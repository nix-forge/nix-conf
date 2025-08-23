{ config, ... }:
{
  programs.ssh.matchBlocks = {
    ugclinux = {
      hostname = "ugclinux.cs.cornell.edu";

      extraOptions = {
        Include = config.age.secrets.cornell-net-id-ssh-config.path;
        SetEnv = "TERM=xterm-256color";
      };
    };
  };
}
