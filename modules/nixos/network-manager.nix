{ config, lib, ... }:
let
  cfg = config.networking.networkManagerBaseline;
in
{
  options.networking.networkManagerBaseline = {
    enable = lib.mkEnableOption "a NetworkManager desktop networking baseline";

    trustedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Existing local accounts permitted to change system network connections
        through NetworkManager. This is deliberately host-local: membership
        grants authority to create and alter system-wide network profiles.
      '';
    };

    wifiBackend = lib.mkOption {
      type = lib.types.enum [
        "wpa_supplicant"
        "iwd"
      ];
      default = "wpa_supplicant";
      description = ''
        Wi-Fi control backend. Keep the choice local: iwd is a good fit when
        it has been tested with the host's adapter, while wpa_supplicant is the
        conservative, broadly compatible NetworkManager default.
      '';
    };

    scanRandMacAddress = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Randomize Wi-Fi scan MAC addresses when supported by the selected
        backend. Connection MAC policy is deliberately left to host-local
        profiles, since a stationary device may need a stable DHCP identity.
      '';
    };

    enableModemManager = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable ModemManager integration. It is off by default because a host
        without a cellular modem does not benefit from an additional privileged
        hardware-management daemon.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.trustedUsers != [ ];
        message = "networking.networkManagerBaseline requires an explicit host-local trustedUsers list.";
      }
      {
        assertion = lib.all (user: builtins.hasAttr user config.users.users) cfg.trustedUsers;
        message = "Every networking.networkManagerBaseline.trustedUsers entry must name an existing local account.";
      }
      {
        assertion = !config.networking.useNetworkd && !config.systemd.network.enable;
        message = "NetworkManager must be the sole owner of physical uplinks; disable systemd-networkd and remove its physical-link profiles before enabling networking.networkManagerBaseline.";
      }
      {
        assertion = config.services.resolved.enable;
        message = "networking.networkManagerBaseline requires systemd-resolved so DNS remains owned by the configured local resolver policy.";
      }
    ];

    networking = {
      # NetworkManager owns DHCP and link configuration.  Do not leave a
      # second DHCP client running alongside it.
      useDHCP = false;
      dhcpcd.enable = false;
      modemmanager.enable = lib.mkForce cfg.enableModemManager;

      networkmanager = {
        enable = true;
        dhcp = "internal";
        logLevel = "WARN";

        # The resolver is an explicit security boundary on this configuration
        # (for example, systemd-resolved -> a local DNS blocker).  Do not let
        # DHCP or VPN connection data replace /etc/resolv.conf or bypass it.
        # services.resolved normally selects NetworkManager's
        # "systemd-resolved" mode. Force "none" here because that mode would
        # publish DHCP/VPN DNS servers to resolved and could bypass the
        # explicitly configured local resolver.
        dns = lib.mkForce "none";

        wifi = {
          backend = cfg.wifiBackend;
          inherit (cfg) scanRandMacAddress;
        };

        connectionConfig = {
          # A desktop must recover from an access-point restart without a
          # manual login. Zero is NetworkManager's documented infinite retry
          # value for profiles that inherit this global default.
          "autoconnect-retries-default" = 0;
        };

        settings = {
          main = {
            # Host identity is declarative; do not accept a DHCP or reverse
            # DNS supplied transient hostname.
            "hostname-mode" = "none";
          };

          connectivity = {
            # Avoid a periodic third-party HTTP probe and its privacy/false
            # portal trade-off. Users can still manage connections with nmcli,
            # nmtui, or a desktop frontend.
            enabled = false;
          };
        };
      };
    };

    # The upstream NixOS module grants NetworkManager polkit authority to this
    # group. Keep it deliberately small and selected by the host.
    users.users = lib.genAttrs cfg.trustedUsers (_: {
      extraGroups = [ "networkmanager" ];
    });
  };
}
