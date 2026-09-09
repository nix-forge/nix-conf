{ lib, myLib, ... }:
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
    secretDirectory = "homes/shared/secrets";
    sharedSecretDirectory = "modules/shared/secrets";
    identityFile = "/Users/ianmh/.ssh/id_ed25519";
    artifactCacheRoot = "/Users/ianmh/Library/Caches/nix-seal/v1";
    repositoryRoot = ../../.;
    identities = {
      target = {
        kind = "target";
        public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
      };
    };
    # Config names select public templates backed by the encrypted fields.
    inherit
      (myLib.secrets.mkTemplates {
        inventoryFiles = [
          ../shared/local/config/secret-templates/inventory.json
          ./local/secret-templates/inventory.json
        ];
        repositoryRoot = ../../.;
        scope = "ianhollow/users/ianmh";
        secrets =
          lib.genAttrs [
            "nix-access-tokens"
            "cornell-net-id-ssh-config"
            "git-allowedsigners"
            "gitconfig-username"
            "gitconfig-useremail"
            "gitconfig-useremail-cornell"
            "gitconfig-useremail-github"
            "hf-token"
          ] (_: runtime)
          // {
            "service-runtime-environment" = runtime // {
              mode = "0600";
              phase = "services";
              restartUnits = [ "local.services.local-control-proxy" ];
            };
          };
      })
      secrets
      templates
      ;
  };
}
