{ lib, ... }: {
  imports = [ ../shared/nix-seal.nix ];
  nixSeal = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
    secrets.smithsonian-open-access-api-key = {
      source = "homes/desktop/local/secrets/smithsonian-open-access-api-key.age";
      serviceCredentials = [
        {
          unit = "desktop-wallpaper-fetch-smithsonian.service";
          name = "smithsonian-open-access-api-key";
        }
      ];
    };
  };
}
