{ ... }:
{
  imports = [ ((import ../../_shared/homelab/network.nix) { profile = "home-server"; }) ];
}
