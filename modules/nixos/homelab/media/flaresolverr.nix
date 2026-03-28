{ pkgs, ... }:
{
  services.flaresolverr = {
    enable = true;
    package = pkgs.flaresolverr;
    port = 8191;
    openFirewall = false;
  };
}
