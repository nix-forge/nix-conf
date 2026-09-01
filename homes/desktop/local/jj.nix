{
  config,
  lib,
  pkgs,
  ...
}:
let
  secretId = "git-allowedsigners";
  hasAllowedSigners = lib.hasAttrByPath [ "nixSeal" "secrets" secretId ] config;
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
      // lib.optionalAttrs hasAllowedSigners {
        allowed-signers = config.nixSeal.secrets.${secretId}.path;
      };
    };

    # Batch interactive SSH signatures when a change is pushed instead of
    # prompting on every amend or rebase.
    git.sign-on-push = true;
  };

  # Reuse the protected Git identity includes without placing identity values
  # in the Nix store. jj reads conf.d after Home Manager's generated config.
  home.activation.jujutsuLocalIdentity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    identity_file=${lib.escapeShellArg identityConfig}
    identity_dir="$(dirname "$identity_file")"
    identity_name="$(${lib.getExe' pkgs.git "git"} config --global --get user.name || true)"
    identity_email="$(${lib.getExe' pkgs.git "git"} config --global --get user.email || true)"

    if [ -z "$identity_name" ] || [ -z "$identity_email" ]; then
      rm -f "$identity_file"
    else
      umask 077
      mkdir -p "$identity_dir"
      chmod 700 "$identity_dir"
      ${lib.getExe pkgs.jq} -nr --arg name "$identity_name" --arg email "$identity_email" \
        '["[user]", "name = \($name | @json)", "email = \($email | @json)", ""] | join("\n")' \
        > "$identity_file"
      chmod 600 "$identity_file"
    fi
  '';
}
