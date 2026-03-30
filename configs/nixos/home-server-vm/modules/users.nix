{
  services.openssh.settings.AllowUsers = [ "testadmin" ];

  users.users.testadmin = {
    isNormalUser = true;
    description = "VM test admin";
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf"
    ];
  };
}
