let
  home-manager-config = extraSpecialArgs: {
    verbose = true;
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm.old";
    inherit extraSpecialArgs;
  };
in
{
  nixos =
    {
      inputs,
      self,
      inputs',
      self',
      system,
      myLib,
      ...
    }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = home-manager-config {
        inherit
          inputs
          self
          inputs'
          self'
          system
          myLib
          ;
      };
    };

  darwin =
    {
      inputs,
      self,
      inputs',
      self',
      system,
      myLib,
      ...
    }:
    {
      imports = [ inputs.home-manager.darwinModules.home-manager ];

      home-manager = home-manager-config {
        inherit
          inputs
          self
          inputs'
          self'
          system
          myLib
          ;
      };
    };
}
