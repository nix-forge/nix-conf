{ lib, ... }:
{
  services.seerr = {
    enable = true;
    port = 5055;
    openFirewall = false;
  };

  users.groups.seerr = { };
  users.users.seerr = {
    isSystemUser = true;
    group = "seerr";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/seerr 0750 seerr seerr - -"
  ];

  systemd.services.seerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "seerr";
    Group = lib.mkForce "seerr";
  };
}
