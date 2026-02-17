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
        nixosConfigurations = lib.filterAttrs (_: x: x.config ? age) self.nixosConfigurations;
        darwinConfigurations = lib.filterAttrs (_: x: x.config ? age) self.darwinConfigurations;
        homeConfigurations = lib.filterAttrs (_: x: x.config ? age) self.homeConfigurations;
        collectHomeManagerConfigurations = true; # useful if a new user is defined using overriding one of the home-manager configurations
      };
    };
}
