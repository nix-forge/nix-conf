{ self, lib, ... }:
{
  imports = [ self.nixOSModules.hardware.networking ];

  networking = {
    generateHostId = true;

    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };

    useDHCP = lib.mkDefault true;
    enableIPv6 = false;

    cloudflareDNS = true;
    randomizeMacAddress = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [
        # 80 # HTTP (uncomment if needed for personal server)
        443 # HTTPS
      ];
    };
  };
}
