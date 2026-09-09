{
  config,
  lib,
  pkgs,
  ...
}:
let
  identityWriter = pkgs.writers.writePython3Bin "write-jujutsu-identity" {
    # Security review comments intentionally exceed Flake8's line limit.
    flakeIgnore = [ "E501" ];
  } ../../modules/home/dev/scripts/write-jujutsu-identity.py;
  runtimeFiles = (config.nixSeal.secrets or { }) // (config.nixSeal.templates or { });
  templatedIdentity =
    builtins.hasAttr "git-user-name" config.nixSeal.secrets
    && builtins.hasAttr "git-user-email" config.nixSeal.secrets;
  secretId = "git-allowedsigners";
  hasAllowedSigners = builtins.hasAttr secretId runtimeFiles;
  identityConfig = "${config.xdg.configHome}/jj/conf.d/90-local-identity.toml";
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
        email.secret = "git-user-email";
      };
    };
  };

  # Reuse the protected Git identity includes without placing identity values
  # in the Nix store. jj reads conf.d after Home Manager's generated config.
  home.activation.jujutsuLocalIdentity =
    if templatedIdentity then
      lib.hm.dag.entryAfter [ "nixSeal" "writeBoundary" ] ''
        identity_file=${lib.escapeShellArg identityConfig}
        identity_dir="$(dirname "$identity_file")"
        umask 077
        mkdir -p "$identity_dir"
        chmod 700 "$identity_dir"
        ${lib.getExe' pkgs.coreutils "ln"} -sfnT -- ${lib.escapeShellArg config.nixSeal.templates.jujutsu-identity.path} "$identity_file"
      ''
    else
      lib.hm.dag.entryAfter [ "nixSeal" "writeBoundary" ] ''
        ${lib.getExe identityWriter} \
          --git ${lib.getExe' pkgs.git "git"} \
          ${lib.escapeShellArg identityConfig}
      '';
}
