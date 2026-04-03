{ ... }:
{
  imports = [ ((import ../../_shared/homelab/integration.nix) { profile = "home-server-vm"; }) ];
}
