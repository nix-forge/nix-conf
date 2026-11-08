{ lib, ... }: {
  imports = [ ../../../shared/local/nix-seal.nix ];
  nixSeal = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./identity.pub);
  };
}
