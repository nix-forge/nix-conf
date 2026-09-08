{
  # Use Apple's launchd-managed server, with the desktop's existing user key.
  services.openssh = {
    enable = true;
    extraConfig = ''
      AllowUsers ianmh
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitEmptyPasswords no
      PubkeyAuthentication yes
      AuthenticationMethods publickey
      UsePAM yes
      AllowAgentForwarding no
      X11Forwarding no
      GatewayPorts no
      PermitTunnel no
      PermitUserEnvironment no
    '';
  };

  users.users.ianmh.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolRZAKwwqDLSkgezpqNK4WYLjMsE1qp8f3k7nYMVgq ianmh@desktop"
  ];
}
