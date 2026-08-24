{ lib, ... }: {
  # A firewall is a safe baseline for physical hosts, but connection managers,
  # DHCP ownership, Wi-Fi backends, interface names, and routing policy are
  # properties of an individual system. Keep those choices in `local/`.
  networking = {
    nftables.enable = lib.mkDefault true;
    firewall = {
      enable = lib.mkDefault true;
      backend = lib.mkDefault "nftables";
    };
  };
}
