{
  services.openssh = {
    enable = true;
    startWhenNeeded = false;
    ports = [ 22 ];
    listenAddresses = [
      {
        addr = "0.0.0.0";
        port = 22;
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
    openFirewall = true;
  };

}
