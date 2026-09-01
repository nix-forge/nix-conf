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
    # Optional source credentials must not make unrelated desktop deployments
    # fail when their encrypted artifact has not been provisioned yet.
    secrets =
      lib.genAttrs
        (
          [
            "nix-access-tokens"
            "cornell-net-id-ssh-config"
            "git-allowedsigners"
            "gitconfig-username"
            "gitconfig-useremail"
            "gitconfig-useremail-cornell"
            "gitconfig-useremail-github"
            "hf-token"
          ]
          ++ [ "smithsonian-open-access-api-key" ]
        )
        (
          name:
          runtime
          // lib.optionalAttrs (name == "smithsonian-open-access-api-key") {
            # This key has not been sealed yet. It remains completely out of
            # desktop activation until delegated first-creation completes.
            pending =
              !builtins.pathExists ../../secrets/ianhollow/users/ianmh/smithsonian-open-access-api-key.age;

            # When the secret is sealed, systemd exposes it only to this fetcher
            # through CREDENTIALS_DIRECTORY. It is neither an environment variable
            # nor a Nix-store input.
            serviceCredentials = [
              {
                unit = "desktop-wallpaper-fetch-smithsonian.service";
                name = "smithsonian-open-access-api-key";
              }
            ];
          }
        );
  };
}
