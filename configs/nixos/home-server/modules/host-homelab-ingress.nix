{ ... }:
{
  imports = [ ((import ../../_shared/homelab/ingress.nix) { profile = "home-server"; }) ];
}
