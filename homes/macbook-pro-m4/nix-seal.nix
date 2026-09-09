{ lib, ... }: {
  imports = [ ../shared/nix-seal.nix ];
  nixSeal = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
    secrets.service-private-settings = {
      source = "homes/macbook-pro-m4/local/secrets/service-private-settings.age";
      mode = "0600";
      phase = "services";
      restartUnits = [ "local.services.local-control-proxy" ];
    };
  };
}
