{
  nixos = { inputs, ... }: { imports = [ inputs.nix-seal.nixosModules.default ]; };

  darwin = { inputs, ... }: { imports = [ inputs.nix-seal.darwinModules.default ]; };

  homeManager = { inputs, ... }: { imports = [ inputs.nix-seal.homeManagerModules.default ]; };
}
