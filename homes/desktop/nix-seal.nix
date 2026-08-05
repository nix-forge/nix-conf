{ lib, ... }:
let
  runtime = {
    owner = "ianmh";
    group = "ianmh";
    mode = "0400";
  };
in
{
  nixSeal = {
    enable = true;
    administrator = "ianhollow";
    identityFile = "/home/ianmh/.ssh/id_ed25519";
    artifactCacheRoot = "/home/ianmh/.cache/nix-seal/v1";
    repositoryRoot = ../../.;
    identities = {
      target = {
        kind = "target";
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEolRZAKwwqDLSkgezpqNK4WYLjMsE1qp8f3k7nYMVgq";
      };
    };
    secrets = lib.genAttrs [
      "nix-access-tokens"
      "cornell-net-id-ssh-config"
      "git-allowedsigners"
      "gitconfig-username"
      "gitconfig-useremail"
      "gitconfig-useremail-cornell"
      "gitconfig-useremail-github"
      "hf-token"
    ] (_: runtime);
  };
}
