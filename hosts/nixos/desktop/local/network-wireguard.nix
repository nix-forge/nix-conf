{
  # This workstation's network topology, peer identities, tunnel addresses,
  # routes, and private-key material are intentionally not guessed. The
  # baseline adds the current native NixOS backend and diagnostic tools, but
  # creates no interface until a reviewed local peer configuration is added.
  networking.wireguardBaseline = {
    enable = true;
    backend = "networkd";
    openFirewallPorts = [ ];
    allowDefaultRoutes = false;
  };

  # When a real tunnel is required, declare it here with a nix-seal runtime
  # privateKeyFile and a peer-specific allowedIPs list. Do not put private or
  # preshared keys in this file, the Nix store, or a world-readable wg-quick
  # configuration. A full-tunnel configuration is a separate routing/DNS
  # project and must explicitly set allowDefaultRoutes = true.
}
