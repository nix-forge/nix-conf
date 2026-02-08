{
  inputs,
  self,
  lib,
  ...
}:
{
  imports = [ inputs.agenix-rekey.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      agenix-rekey = {
        inherit pkgs;
        nixosConfigurations = lib.filterAttrs (_: x: x.config ? age) (
          self.nixosConfigurations // self.darwinConfigurations
        );
        homeConfigurations = lib.filterAttrs (_: x: x.config ? age) self.homeConfigurations;
        collectHomeManagerConfigurations = true; # useful if defining another user with new ssh key based on a defined home configuration
      };
    };
}
