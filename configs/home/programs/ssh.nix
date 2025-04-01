{ lib, ... }:
{
  programs.ssh = {
    enable = true;

    # Automatically add keys to ssh-agent when used
    addKeysToAgent = "yes";

    # Improve performance slightly for slow connections
    compression = true;

    # Enable SSH connection multiplexing (nice for git/ssh)
    controlMaster = "auto";
    controlPath = "~/.ssh/master-%r@%n:%p";
    controlPersist = "10m"; # Reuse SSH connections for 10 minutes

    # Improve security & convenience
    hashKnownHosts = true;
    forwardAgent = lib.mkForce false; # Avoid using unless you need to forward your SSH key
    serverAliveInterval = 60;
    serverAliveCountMax = 3;
  };
}
