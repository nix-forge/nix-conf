{ lib, nixSealTrust, ... }:
let
  targetId = "home/ianmh/macbook-pro-m4";
  sources = {
    "ianhollow/users/ianmh/nix-access-tokens" = "secrets/users/ianmh/nix-access-tokens.age";
    "ianhollow/users/ianmh/cornell-net-id-ssh-config" =
      "secrets/users/ianmh/cornell-net-id-ssh-config.age";
    "ianhollow/users/ianmh/git-allowedsigners" = "secrets/users/ianmh/git-allowedsigners.age";
    "ianhollow/users/ianmh/gitconfig-username" = "secrets/users/ianmh/gitconfig-username.age";
    "ianhollow/users/ianmh/gitconfig-useremail" = "secrets/users/ianmh/gitconfig-useremail.age";
    "ianhollow/users/ianmh/gitconfig-useremail-cornell" =
      "secrets/users/ianmh/gitconfig-useremail-cornell.age";
    "ianhollow/users/ianmh/gitconfig-useremail-github" =
      "secrets/users/ianmh/gitconfig-useremail-github.age";
    "ianhollow/users/ianmh/hf-token" = "secrets/users/ianmh/hf-token.age";
  };
  runtime = {
    owner = "ianmh";
    group = "staff";
    mode = "0400";
  };
in
{
  nixSeal = {
    enable = true;
    inherit targetId;
    identityFile = "/Users/ianmh/.ssh/id_ed25519";
    artifactCacheRoot = "/Users/ianmh/Library/Caches/nix-seal/v1";
    repositoryRoot = ../../.;
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
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
      };
    };
    target = {
      kind = "homeManager";
      system = "aarch64-darwin";
      username = "ianmh";
      configuration = "macbook-pro-m4";
      identity = "target";
    };
    approvalPolicies.release = {
      threshold = 1;
      signers = [ "release" ];
    };
    secrets = lib.mapAttrs (
      _: source:
      runtime
      // {
        inherit source;
        administrators = [
          "administrator"
          "recovery"
        ];
        approvalPolicy = "release";
      }
    ) sources;
  };
}
