{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Give the browser's import picker a stable JSON filename. Link to the
  # current sealed generation instead of copying plaintext into another file.
  # User tmpfiles recreates the link at login and Home Manager activation.
  systemd.user.tmpfiles.rules = lib.mkIf pkgs.stdenv.hostPlatform.isLinux [
    "d ${builtins.toJSON config.nixSeal.runtimeDirectory} 0700 - - -"
    "L+ ${builtins.toJSON "${config.nixSeal.runtimeDirectory}/refined-github-token-import.json"} - - - - ${
      lib.strings.escapeC [
        "\\"
        " "
        "\n"
        "\r"
        "\t"
      ] config.nixSeal.templates.refined-github-token-import.path
    }"
  ];

  nixSeal = {
    secretDirectory = "homes/shared/local/secrets";
    sharedSecretDirectory = "homes/shared/local/secrets";

    secrets = [
      "cornell-net-id"
      "git-privacy-policy"
      "git-user-name"
      "git-user-email"
      "git-user-email-cornell"
      "git-user-email-github"
      "hf-token"
      "refined-github-token"
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
      # Use the dedicated Refined GitHub credential through its supported
      # Import UI. Keep the rendered token out of browser policies.
      # GitHub token values contain only JSON-safe letters, digits and underscores.
      refined-github-token-import = {
        mode = "0400";
        content = builtins.toJSON {
          __webextOptionsSync = "Refined GitHub";
          personalToken = [ "{{nix-seal:refined-github-token}}" ];
        };
      };
      git-allowedsigners = {
        content = ''
          {{nix-seal:git-user-email}} namespaces="git" {{public:signing-key}}
          {{nix-seal:git-user-email-github}} namespaces="git" {{public:signing-key}}
          {{nix-seal:git-user-email-cornell}} namespaces="git" {{public:signing-key}}
        '';
        publicValues.signing-key = lib.removeSuffix "\n" (
          builtins.readFile ../../macbook-pro-m4/local/nix-seal/identity.pub
        );
      };
    };
  };
}
