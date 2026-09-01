{ config, lib, ... }:
let
  cfg = config.networking.wirelessIwd;
in
{
  options.networking.wirelessIwd = {
    enable = lib.mkEnableOption "the IWD plus systemd-networkd wireless baseline";

    macAddressPolicy = lib.mkOption {
      type = lib.types.enum [
        "disabled"
        "once"
        "network"
      ];
      default = "network";
      description = ''
        IWD MAC-address randomization policy. `network` derives a stable,
        locally administered address for each SSID, preserving reliable DHCP
        leases on repeat visits without exposing the adapter's permanent MAC.
        Hosts with a legitimate fixed-MAC requirement override this locally.
      '';
    };

    managementFrameProtection = lib.mkOption {
      type = lib.types.enum [
        "optional"
        "required"
      ];
      default = "optional";
      description = ''
        IEEE 802.11w Protected Management Frames policy. `optional` uses PMF
        whenever both the adapter and access point support it; `required`
        refuses networks that cannot provide it and belongs in a host-local,
        compatibility-tested policy.
      '';
    };

    autoConnect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Reconnect automatically to known wireless profiles.";
    };

    periodicScanning = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Allow IWD's normal background scanning for reconnection and roaming.
        Disable only on a measured power-sensitive host where the resulting
        loss of network discovery is acceptable.
      '';
    };

    hotspot20 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable ANQP queries for Hotspot 2.0 / Passpoint discovery. This stays
        off by default because it is unnecessary on ordinary trusted WLANs and
        adds public-action-frame traffic; select it locally when required.
      '';
    };

    pmksaCaching = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Retain PMKSA caching for faster WPA2/WPA3 reconnection and roaming.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.networking.wireless.enable;
        message = "networking.wirelessIwd requires IWD to be the only Wi-Fi supplicant; disable networking.wireless (wpa_supplicant).";
      }
      {
        assertion = config.networking.useNetworkd;
        message = "networking.wirelessIwd leaves addressing, routes, and DNS to systemd-networkd, so networking.useNetworkd must be enabled.";
      }
      {
        assertion = !config.networking.networkmanager.enable;
        message = "networking.wirelessIwd is an IWD plus systemd-networkd profile and cannot share Wi-Fi ownership with NetworkManager.";
      }
    ];

    networking.wireless.iwd = {
      enable = true;
      settings = {
        General = {
          # IWD owns radio association only. networkd owns link addressing and
          # routing; resolved and the local DNS policy own name resolution.
          EnableNetworkConfiguration = false;

          AddressRandomization = cfg.macAddressPolicy;
          AddressRandomizationRange = "full";

          # Optional PMF is the interoperable secure default. IWD still makes
          # PMF mandatory for 6 GHz, where the standard requires it.
          ManagementFrameProtection = if cfg.managementFrameProtection == "required" then 2 else 1;

          # Preserve IWD's secure/stable defaults explicitly: avoid ANQP until
          # a host needs Passpoint, while retaining PMKSA for fast WPA roaming.
          DisableANQP = !cfg.hotspot20;
          DisablePMKSA = !cfg.pmksaCaching;
        };

        Settings.AutoConnect = cfg.autoConnect;
        Scan.DisablePeriodicScan = !cfg.periodicScanning;
      };
    };
  };
}
