{ lib, ... }:
{
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    jails.sshd.settings.enabled = true;
  };

  services.openssh.settings.LogLevel = lib.mkDefault "VERBOSE";
}
