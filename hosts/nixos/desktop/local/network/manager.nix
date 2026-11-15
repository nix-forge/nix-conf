{
  # This desktop intentionally remains on systemd-networkd + iwd today. It is
  # a stationary, remotely administered workstation with a tested IWD profile;
  # NetworkManager would add interactive connection management but no material
  # performance or security benefit. Keeping this decision local preserves the
  # reusable NetworkManager baseline for a future roaming/VPN-oriented host.
  networking.networkManagerBaseline = {
    enable = false;
    trustedUsers = [ "ianmh" ];
    # Preserve the adapter backend already proven with the desktop's MT7921e
    # radio. IWD itself owns scan-MAC behavior, so keep this matching its
    # existing stable-address policy for the trusted home LAN.
    wifiBackend = "iwd";
    scanRandMacAddress = false;
    enableModemManager = false;
  };

  # A future, deliberately tested migration belongs here. It must select the
  # local administrator, adapter backend, connection profiles, MAC policy, and
  # then remove the physical-link systemd-networkd profiles in
  # local/hardware/networking.nix before enabling the baseline.
}
