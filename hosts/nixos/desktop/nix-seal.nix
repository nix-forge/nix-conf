_: {
  nixSeal = {
    enable = true;
    administrator = "ianhollow";
    identityFile = "/etc/ssh/ssh_host_ed25519_key";
    artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
    repositoryRoot = ../../../.;
    identities = {
      target = {
        kind = "target";
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwSeiaY3PpNjPDaFA9bDPeFaLU5HYi0PrJKEEYIt3Vs";
      };
    };
    secrets."nix-access-tokens" = {
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
