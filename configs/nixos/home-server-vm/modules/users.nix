{
  services.openssh.settings.AllowUsers = [ "testadmin" ];

  users.users.testadmin = {
    isNormalUser = true;
    description = "VM test admin";
    extraGroups = [
      "wheel"
      "media"
    ];
    initialPassword = "changeme";
  };
}
