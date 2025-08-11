{
  config,
  lib,
  tree,
  pkgs,
  ...
}:
let
  addUser = lib.cust.darwin.addUser { inherit config lib pkgs; };
  homes = name: tree.homes.${name}.modules;
in
lib.mkMerge [
  # NOTE: Any users that need a working password must be created before defining them here
  (addUser {
    username = "ianmh";
    description = "Ian Holloway";
    homeManagerModules = homes "macbook-pro-m4";
    shell = pkgs.nushell;
    knownUser = true;
    uid = 501;
  })
]
