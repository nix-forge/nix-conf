{ config, inputs, ... }: {
  imports = [ inputs.nix-homelab.nixosModules.default ];

  # The provider profile stays public host configuration, but the WireGuard
  # private key is delivered only at service activation time. Declaring it now
  # makes nix-seal expose the create-only bootstrap workflow without placing a
  # credential in this expression or the Nix store.
  nixSeal.secrets.homelab-vpn-private-key.phase = "services";

  homelab = {
    # Apply the shared-desktop scheduling policy now. Media applications remain
    # disabled until the existing disk contents, capacity budget, recovery
    # destination, VPN profile and application secrets are ready.
    profiles.desktop.enable = true;

    # Mullvad's assigned addresses and relay material are public provider
    # configuration. Pinning a literal, currently active endpoint avoids host
    # DNS before the tunnel exists. This Seattle relay had the lowest measured
    # latency of the active local relays at enrollment time; remeasure instead
    # of assuming that a particular relay remains fastest forever.
    vpn = {
      interface = {
        privateKeyFile = config.nixSeal.secrets.homelab-vpn-private-key.path;
        addressIPv4 = "10.69.242.111";
        addressIPv6 = "fc00:bbbb:bbbb:bb01::6:f26e";
        dns = [ "10.64.0.1" ];
        mtu = 1380;
      };
      peer = {
        publicKey = "tfhYXF12+7tB6bEOhqZ7eMODDv08fDMnQSBTmlau9VI=";
        endpointHost = "23.234.83.127";
        endpointPort = 51820;
      };
    };

    # This external-disk path is independent of the internal NVMe Disko layout,
    # so application databases do not need a path migration later. Downloads
    # and the organized library remain below one ext4 mount for hardlink imports.
    storage = {
      rootDir = "/mnt/homelab/media";
      requiredMounts = [ "/mnt/homelab" ];
    };

    # Preserve substantial working room for the existing Restic repository on
    # this shared disk. These thresholds become active with the authenticated
    # downloader pressure controller; setting them now avoids its much smaller
    # generic defaults when the remaining application credentials are added.
    operations.pressure = {
      pauseBytes = 1024 * 1024 * 1024 * 1024;
      resumeBytes = 1152 * 1024 * 1024 * 1024;
    };
  };
}
