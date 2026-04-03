{ ... }:
{
  imports = [ ((import ../../_shared/homelab/services.nix) { profile = "home-server"; }) ];
}
