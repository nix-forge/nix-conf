{
  nixos =
    {
      inputs,
      lib,
      nixSealTarget ? null,
      ...
    }:
    {
      imports = [ inputs.nix-seal.nixosModules.default ];

      config = lib.mkIf (nixSealTarget != null && nixSealTarget.enable) {
        nixSeal = {
          enable = true;
          inherit (nixSealTarget)
            targetId
            identityFile
            planObjects
            secrets
            ;
        };
      };
    };

  darwin =
    {
      inputs,
      lib,
      nixSealTarget ? null,
      ...
    }:
    {
      imports = [ inputs.nix-seal.darwinModules.default ];

      config = lib.mkIf (nixSealTarget != null && nixSealTarget.enable) {
        nixSeal = {
          enable = true;
          inherit (nixSealTarget)
            targetId
            identityFile
            planObjects
            secrets
            ;
        };
      };
    };

  homeManager =
    {
      inputs,
      lib,
      nixSealTarget ? null,
      ...
    }:
    {
      imports = [ inputs.nix-seal.homeManagerModules.default ];

      config = lib.mkIf (nixSealTarget != null && nixSealTarget.enable) {
        nixSeal = {
          enable = true;
          inherit (nixSealTarget)
            targetId
            identityFile
            planObjects
            secrets
            ;
        };
      };
    };
}
