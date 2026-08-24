{ config, lib, ... }:
let
  homeDirectory = config.home.homeDirectory;
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
    identityFile = "${homeDirectory}/.ssh/id_ed25519";
    artifactCacheRoot = "${homeDirectory}/.cache/nix-seal/v1";
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
