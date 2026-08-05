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
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
      };
    };
    secrets."nix-access-tokens" = {
      owner = "root";
      group = "wheel";
      mode = "0400";
    };
  };
}
