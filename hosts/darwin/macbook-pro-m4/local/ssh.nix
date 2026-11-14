{ lib, ... }: {
  # Use Apple's launchd-managed server, with the desktop's existing key.
  services.openssh = {
    enable = true;
    extraConfig = ''
      AllowUsers ianmh root
      PermitRootLogin prohibit-password
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
      Match User root
        SetEnv PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin
    '';
  };

  users.users.ianmh.openssh.authorizedKeys.keys = [
    "${lib.removeSuffix "\n" (builtins.readFile ../../../../homes/desktop/local/nix-seal/identity.pub)} ianmh@desktop"
  ];

  # A nix-darwin deployment runs arbitrary root activation code. Authorize
  # the existing desktop key directly for root and disable SSH forwarding and
  # TTY access for this deployment credential.
  users.users.root.openssh.authorizedKeys.keys = [
    "restrict ${lib.removeSuffix "\n" (builtins.readFile ../../../../homes/desktop/local/nix-seal/identity.pub)} deployment-client"
  ];
}
