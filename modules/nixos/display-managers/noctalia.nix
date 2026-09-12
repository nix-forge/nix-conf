{ pkgs, ... }:
{
  services.displayManager.noctalia-greeter = {
    enable = true;
    package = pkgs.noctalia-greeter-personal;
  };
}
