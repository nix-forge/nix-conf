{
  networking.wirelessIwd = {
    enable = true;

    # This stationary desktop is deliberately identified by a stable MAC on
    # its trusted LAN: SSH and Sunshine clients use its DHCP identity. Mobile
    # hosts should keep the shared per-network randomized-MAC default instead.
    macAddressPolicy = "disabled";
  };

  networking.wireless.iwd.settings = {
    General = {
      # Regulatory domain is physical-location policy, not a shared default.
      Country = "US";
    };

    DriverQuirks = {
      # The MediaTek MT7922 adapter in this mains-powered desktop exhibits
      # lower latency and more consistent throughput with Wi-Fi power save
      # disabled. Do not copy this hardware-specific quirk to other hosts.
      PowerSaveDisable = "mt7921e";
    };
  };
}
