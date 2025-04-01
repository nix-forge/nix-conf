{ inputs, ... }:
let
  secrets = inputs.nix-secrets;

  rootAccess = {
    mode = "0500"; # read and execute only
    owner = "root";
  };
in
{
  age.secrets.githubAccessToken = {
    file = "${secrets}/shared/nix-github-access-token.age";
  } // rootAccess;
}
