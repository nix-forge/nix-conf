{ lib, ... }:
{
  services.fail2ban = {
    maxretry = lib.mkDefault 5;
    bantime = lib.mkDefault "1h";
    jails.sshd.settings.enabled = lib.mkDefault true;
  };

  services.openssh.settings.LogLevel = lib.mkDefault "VERBOSE";
}
