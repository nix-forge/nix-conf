{ lib, ... }: {
  nixSeal = {
    secretDirectory = "homes/shared/secrets";
    sharedSecretDirectory = "modules/shared/secrets";

    secrets = [
      "cornell-net-id"
      "git-user-name"
      "git-user-email"
      "git-user-email-cornell"
      "git-user-email-github"
      "hf-token"
      { nix-token-github-com.shared = true; }
    ];
    templates = {
      cornell-net-id-ssh-config = ''
        User {{nix-seal:cornell-net-id}}
      '';
      gitconfig-username = ''
        [user]
            name = "{{nix-seal:git-user-name}}"
      '';
      gitconfig-useremail = ''
        [user]
            email = "{{nix-seal:git-user-email}}"
      '';
      gitconfig-useremail-cornell = ''
        [user]
            email = "{{nix-seal:git-user-email-cornell}}"
      '';
      gitconfig-useremail-github = ''
        [user]
            email = "{{nix-seal:git-user-email-github}}"
      '';
      nix-access-tokens = ''
        access-tokens = github.com={{nix-seal:nix-token-github-com}}
      '';
      git-allowedsigners = {
        content = ''
          {{nix-seal:git-user-email}} namespaces="git" {{public:signing-key}}
          {{nix-seal:git-user-email-github}} namespaces="git" {{public:signing-key}}
          {{nix-seal:git-user-email-cornell}} namespaces="git" {{public:signing-key}}
        '';
        publicValues.signing-key = lib.removeSuffix "\n" (
          builtins.readFile ../macbook-pro-m4/local/nix-seal/identity.pub
        );
      };
    };
  };
}
