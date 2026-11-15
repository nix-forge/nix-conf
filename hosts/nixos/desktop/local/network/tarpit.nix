{
  # This Wi-Fi desktop has no public SSH listener: its default-drop nftables
  # policy and SSH-only private-network rule are safer and use fewer resources
  # than a decoy service. Enable this only for a deliberately selected decoy
  # network/source scope, preferably on a dedicated monitored host.
  networking.tarpit.enable = false;
}
