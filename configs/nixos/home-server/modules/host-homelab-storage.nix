{ ... }:
{
  imports = [ ((import ../../_shared/homelab/storage.nix) { profile = "home-server"; }) ];
}
