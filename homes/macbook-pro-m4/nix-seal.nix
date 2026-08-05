{ lib, ... }:
let
  runtime = {
    owner = "ianmh";
    group = "staff";
    mode = "0400";
  };
in
{
  nixSeal = {
    enable = true;
    administrator = "ianhollow";
    identityFile = "/Users/ianmh/.ssh/id_ed25519";
    artifactCacheRoot = "/Users/ianmh/Library/Caches/nix-seal/v1";
    repositoryRoot = ../../.;
    identities = {
      target = {
        kind = "target";
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
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
