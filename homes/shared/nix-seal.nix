{ lib, ... }: {
  nixSeal = {
    secretDirectory = "homes/shared/secrets";
    sharedSecretDirectory = "modules/shared/secrets";
    templateDirectory = "homes/shared/templates";

    secrets = [
      "cornell-net-id"
      "git-user-name"
      "git-user-email"
      "git-user-email-cornell"
      "git-user-email-github"
      "hf-token"
      { nix-token-github-com.shared = true; }
    ];
    templates = [
      { cornell-net-id-ssh-config = ./templates/cornell-net-id-ssh.conf.template; }
      {
        git-allowedsigners.publicValues.signing-key = lib.removeSuffix "\n" (
          builtins.readFile ../macbook-pro-m4/local/nix-seal/identity.pub
        );
      }
      { gitconfig-username = ./templates/gitconfig-username.gitconfig.template; }
      { gitconfig-useremail = ./templates/gitconfig-useremail.gitconfig.template; }
      { gitconfig-useremail-cornell = ./templates/gitconfig-useremail-cornell.gitconfig.template; }
      { gitconfig-useremail-github = ./templates/gitconfig-useremail-github.gitconfig.template; }
      { nix-access-tokens = ../../modules/shared/templates/nix-access-tokens.conf.template; }
    ];
  };
}
