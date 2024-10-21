{
  lib,
  ...
}:
{
  networking = {
    networkmanager = {
      wifi.backend = "iwd";
    };

    # global dhcp has been deprecated upstream
    # use the new networkd service instead of the legacy
    # "script-based" network setups. Host may contain individual
    # dhcp interfaces or systemd-networkd configurations in host
    # specific directories
    useDHCP = lib.mkForce false;
    useNetworkd = true;

    # stevenblack = {
    #   enable = true;
    #   block = [
    #     "fakenews"
    #     "gambling"
    #     "porn"
    #   ];
    # };
  };
}
