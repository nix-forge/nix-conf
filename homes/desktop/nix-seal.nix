{ lib, nixSealTrust, ... }:
let
  targetId = "home/ianmh/desktop";
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
    group = "ianmh";
    mode = "0400";
  };
in
{
  nixSeal = {
    enable = true;
    inherit targetId;
    identityFile = "/home/ianmh/.ssh/id_ed25519";
    artifactCacheRoot = "/home/ianmh/.cache/nix-seal/v1";
    repositoryRoot = ../../.;
    secrets = lib.mapAttrs (_: source: runtime // { inherit source; }) sources;
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
          public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolRZAKwwqDLSkgezpqNK4WYLjMsE1qp8f3k7nYMVgq";
        };
      };
      targets.${targetId} = {
        kind = "homeManager";
        system = "x86_64-linux";
        username = "ianmh";
        configuration = "desktop";
        identity = "target";
      };
      secrets = lib.mapAttrs (_: source: {
        inherit source;
        consumers = [ targetId ];
        administrators = [
          "administrator"
          "recovery"
        ];
        approvalPolicy = "release";
        inherit runtime;
      }) sources;
      approvalPolicies.release = {
        threshold = 1;
        signers = [ "release" ];
      };
    };
  };
}
