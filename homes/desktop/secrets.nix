{ inputs, config, ... }:
let
  secrets = inputs.nix-secrets;
  usersSecrets = "${secrets}/users/${config.home.username}";
in
{
  age.secrets.gitUserName.file = "${usersSecrets}/git-userName.age";
  age.secrets.gitUserEmail.file = "${usersSecrets}/git-userEmail.age";
}
