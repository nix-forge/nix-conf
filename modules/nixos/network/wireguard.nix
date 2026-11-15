{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.networking.wireguardBaseline;
  interfaces = config.networking.wireguard.interfaces;
  peers = lib.concatMap (interface: interface.peers) (lib.attrValues interfaces);
  defaultRoutes = [
    "0.0.0.0/0"
    "::/0"
  ];
  isStorePath = path: lib.hasPrefix "/nix/store/" path;
in
{
  options.networking.wireguardBaseline = {
    enable = lib.mkEnableOption "a declarative WireGuard baseline";

    backend = lib.mkOption {
      type = lib.types.enum [
        "networkd"
        "script"
      ];
      default = "networkd";
      description = ''
        Backend for NixOS's native `networking.wireguard.interfaces` module.
        `networkd` is the preferred choice for hosts that already use
        systemd-networkd; `script` is retained for hosts that cannot use it.
        This is deliberately not a NetworkManager profile, so tunnel routing
        and DNS ownership remain declarative and reviewable.
      '';
    };

    openFirewallPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = ''
        UDP listener ports to permit through the host firewall. A client-only
        tunnel normally needs none; declare a port only when this host must
        accept unsolicited WireGuard handshakes.
      '';
    };

    allowDefaultRoutes = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow peers to claim `0.0.0.0/0` or `::/0`. Full-tunnel VPNs require
        endpoint-exception routing, DNS, and an optional kill-switch design,
        so this acknowledgement must be explicitly host-local.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The native NixOS module loads the in-kernel driver and supplies the
    # appropriate systemd/networkd integration only when interfaces exist.
    # Keep the tool available for `wg show` and local key generation without
    # creating a tunnel or opening a port by default.
    environment.systemPackages = [ pkgs.wireguard-tools ];

    networking = {
      wireguard.useNetworkd = lib.mkDefault (cfg.backend == "networkd");
      firewall.allowedUDPPorts = cfg.openFirewallPorts;
    };

    assertions = [
      {
        assertion =
          !config.networking.wireguard.enable
          || config.networking.wireguard.useNetworkd == (cfg.backend == "networkd");
        message = "networking.wireguardBaseline.backend must match networking.wireguard.useNetworkd.";
      }
      {
        assertion =
          !config.networking.wireguard.enable
          || cfg.backend != "networkd"
          || (config.networking.useNetworkd && config.systemd.network.enable);
        message = "The WireGuard networkd backend requires systemd-networkd to own the host network configuration.";
      }
      {
        assertion = !config.networking.wireguard.enable || config.networking.wg-quick.interfaces == { };
        message = "Use either networking.wireguard.interfaces or networking.wg-quick.interfaces, not both; this baseline standardizes on the native WireGuard module.";
      }
      {
        assertion = lib.all (
          interface:
          interface.privateKey == null
          && interface.privateKeyFile != null
          && !isStorePath interface.privateKeyFile
        ) (lib.attrValues interfaces);
        message = "Every WireGuard interface must use a privateKeyFile outside /nix/store (for example a nix-seal runtime secret), never privateKey.";
      }
      {
        assertion = lib.all (
          peer:
          peer.presharedKey == null && (peer.presharedKeyFile == null || !isStorePath peer.presharedKeyFile)
        ) peers;
        message = "WireGuard preshared keys, when used, must use presharedKeyFile outside /nix/store.";
      }
      {
        assertion =
          cfg.allowDefaultRoutes
          || lib.all (peer: lib.all (cidr: !lib.elem cidr defaultRoutes) peer.allowedIPs) peers;
        message = "A WireGuard peer requests a default route. Set networking.wireguardBaseline.allowDefaultRoutes = true only with an explicitly reviewed full-tunnel routing and DNS design.";
      }
      {
        assertion = lib.all (
          port: lib.elem port (map (interface: interface.listenPort) (lib.attrValues interfaces))
        ) cfg.openFirewallPorts;
        message = "Every networking.wireguardBaseline.openFirewallPorts entry must match a declared WireGuard interface listenPort.";
      }
      {
        assertion = lib.all (
          peer:
          peer.persistentKeepalive == null
          || (peer.endpoint != null && peer.persistentKeepalive >= 1 && peer.persistentKeepalive <= 65535)
        ) peers;
        message = "WireGuard PersistentKeepalive is only valid for an endpoint peer and must be in the 1–65535 second range.";
      }
    ];
  };
}
