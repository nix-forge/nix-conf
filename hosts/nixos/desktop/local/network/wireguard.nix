{ config, ... }: {
  # The desktop uses networkd for physical links. The homelab WireGuard client
  # must use the native script backend because its interface is moved into the
  # confined namespace. Its default route and DNS stay inside that namespace.
  networking.wireguardBaseline = {
    enable = true;
    backend = if config.homelab.vpn.enable then "script" else "networkd";
    openFirewallPorts = [ ];
    allowDefaultRoutes = config.homelab.vpn.enable;
  };
}
