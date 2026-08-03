{ nixSealTrust, ... }:
let
  targetId = "host/darwin/macbook-pro-m4";
  secretId = "ianhollow/hosts/darwin/macbook-pro-m4/nix-access-tokens";
in
{
  nixSeal = {
    enable = true;
    inherit targetId;
    identityFile = "/etc/ssh/ssh_host_ed25519_key";
    artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
    repositoryRoot = ../../../.;
    secrets.${secretId} = {
      source = "secrets/hosts/darwin/macbook-pro-m4/nix-access-tokens.age";
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
          public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
        };
      };
      targets.${targetId} = {
        kind = "darwin";
        system = "aarch64-darwin";
        configuration = "macbook-pro-m4";
        identity = "target";
      };
      secrets.${secretId} = {
        source = "secrets/hosts/darwin/macbook-pro-m4/nix-access-tokens.age";
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
