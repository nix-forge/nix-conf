{ lib, ... }: {
  imports = [ ../../../shared/local/nix-seal.nix ];
  nixSeal = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./identity.pub);
    secrets.desktop-homelab-hdd-recovery-key = {
      source = "homes/macbook-pro-m4/local/secrets/desktop-homelab-hdd-recovery-key.age";
      mode = "0600";
      phase = "services";
    };
  };
}
