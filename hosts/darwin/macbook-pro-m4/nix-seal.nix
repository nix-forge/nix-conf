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
    target = {
      kind = "darwin";
      system = "aarch64-darwin";
      configuration = "macbook-pro-m4";
      identity = "target";
    };
    approvalPolicies.release = {
      threshold = 1;
      signers = [ "release" ];
    };
    secrets.${secretId} = {
      source = "secrets/hosts/darwin/macbook-pro-m4/nix-access-tokens.age";
      administrators = [
        "administrator"
        "recovery"
      ];
      approvalPolicy = "release";
      owner = "root";
      group = "wheel";
      mode = "0400";
    };
  };
}
