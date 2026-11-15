{
  config,
  lib,
  pkgs,
  ...
}:
let
  runtimeFiles = (config.nixSeal.secrets or { }) // (config.nixSeal.templates or { });
  templatedIdentity =
    builtins.hasAttr "git-user-name" config.nixSeal.secrets
    && builtins.hasAttr "git-user-email-github" config.nixSeal.secrets;
  secretId = "git-allowedsigners";
  hasAllowedSigners = builtins.hasAttr secretId runtimeFiles;
in
{
  programs.jujutsu.settings = {
    signing = {
      behavior = "drop";
      backend = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      backends.ssh = {
        program = lib.getExe' pkgs.openssh "ssh-keygen";
      }
      // lib.optionalAttrs hasAllowedSigners { allowed-signers = runtimeFiles.${secretId}.path; };
    };

    # Batch interactive SSH signatures when a change is pushed instead of
    # prompting on every amend or rebase.
    git.sign-on-push = true;
  };

  nixSeal.templates = lib.optionalAttrs templatedIdentity {
    jujutsu-identity = {
      content = ''
        [user]
        name = "{{nix-seal:name}}"
        email = "{{nix-seal:email}}"
      '';
      placeholders = {
        name.secret = "git-user-name";
        email.secret = "git-user-email-github";
      };
    };
  };

  programs.jujutsu.runtimeIdentity = {
    enable = true;
    sourceFile = if templatedIdentity then config.nixSeal.templates.jujutsu-identity.path else null;
    activationAfter = [ "nixSeal" ];
  };
}
