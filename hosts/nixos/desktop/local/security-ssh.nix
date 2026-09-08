{
  # This is the MacBook host key already used by its nix-seal identity.
  # Keep a stable alias so a DHCP address change cannot bypass key checking.
  programs.ssh.knownHosts.macbook = {
    hostNames = [ "macbook" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
  };

  # This physical desktop is administered from trusted private networks only.
  # Keep its reachability adjacent to other host-local operational choices;
  # shared policy must not assume a port, account list, or deployment scheme.
  services.openssh = {
    ports = [ 22 ];
    openFirewall = false;
    startWhenNeeded = false;

    settings = {
      AllowUsers = [
        "ianmh"
        "root"
      ];

      # deploy-rs activates this NixOS host through a restricted root public
      # key.  `prohibit-password` keeps that non-interactive recovery path
      # available while rejecting root password and keyboard-interactive login.
      # The root key itself carries OpenSSH's `restrict` option; normal human
      # administration uses the `ianmh` account.
      PermitRootLogin = "prohibit-password";

      # This workstation is administered by one person, not a shared NAT.
      # Keep the per-source admission limit local because it can be too strict
      # for a multi-user server behind a single source address.
      PerSourceMaxStartups = 3;
    };
  };
}
