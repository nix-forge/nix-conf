{ config, ... }:
{
  services.openssh.settings.AllowUsers = [ "ianmh" ];

  users.users.ianmh = {
    isNormalUser = true;
    description = "Ian Holloway";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf"
    ];
    hashedPasswordFile = config.age.secrets.ianmh-password.path;
  };
}
