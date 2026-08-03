{ nixSealTrust, ... }:
let
  targetId = "host/nixos/desktop";
  secretId = "ianhollow/hosts/nixos/desktop/nix-access-tokens";
in
{
  nixSeal = {
    enable = true;
    inherit targetId;
    identityFile = "/etc/ssh/ssh_host_ed25519_key";
    artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
    repositoryRoot = ../../../.;
    secrets.${secretId} = {
      source = "secrets/hosts/nixos/desktop/nix-access-tokens.age";
      owner = "root";
      group = "root";
      mode = "0400";
    };
    planObjects = {
      identities = {
        administrator = {
          kind = "administrator";
          public = nixSealTrust.administratorRecipient;
        };
        recovery = {
          kind = "recovery";
          public = nixSealTrust.recoveryRecipient;
        };
        release = {
          kind = "signer";
          public = nixSealTrust.signerPublicKey;
        };
        target = {
          kind = "target";
          public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwSeiaY3PpNjPDaFA9bDPeFaLU5HYi0PrJKEEYIt3Vs";
        };
      };
      targets.${targetId} = {
        kind = "nixOs";
        system = "x86_64-linux";
        configuration = "desktop";
        identity = "target";
      };
      secrets.${secretId} = {
        source = "secrets/hosts/nixos/desktop/nix-access-tokens.age";
        consumers = [ targetId ];
        administrators = [
          "administrator"
          "recovery"
        ];
        approvalPolicy = "release";
        runtime = {
          owner = "root";
          group = "root";
          mode = "0400";
        };
      };
      approvalPolicies.release = {
        threshold = 1;
        signers = [ "release" ];
      };
    };
  };
}
