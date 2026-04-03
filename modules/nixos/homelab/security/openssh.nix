{ lib, ... }:
{
  services.openssh = {
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = lib.mkDefault false;
      PermitRootLogin = lib.mkDefault "prohibit-password";
      X11Forwarding = lib.mkDefault false;
    };
    openFirewall = lib.mkDefault false;
  };
}
