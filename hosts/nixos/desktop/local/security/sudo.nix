{ lib, ... }: {
  security = {
    sudo = {
      # This owner-administered desktop has one administrator group.  The
      # password prompt and executable permission are intentional: `ianmh` is
      # in wheel; service and sandbox accounts are not allowed to invoke sudo.
      wheelNeedsPassword = true;
      execWheelOnly = lib.mkForce true;
      defaultOptions = [ "NOSETENV" ];
    };

    pam = {
      # NixOS's sudo module supports SSH-agent and SSH-certificate PAM paths
      # when their global backends are enabled.  This graphical account has a
      # GCR SSH agent, but sudo must require the account password instead of a
      # signature available through that session socket.
      sshAgentAuth.enable = false;
      ussh.enable = false;
      services.sudo = {
        sshAgentAuth = lib.mkForce false;
        usshAuth = lib.mkForce false;
      };
    };
  };
}
