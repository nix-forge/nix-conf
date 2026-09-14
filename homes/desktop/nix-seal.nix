{ lib, ... }: {
  imports = [ ../shared/nix-seal.nix ];
  nixSeal = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
  };
}
