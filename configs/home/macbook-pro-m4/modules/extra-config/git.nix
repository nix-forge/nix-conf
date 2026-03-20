{ config, lib, ... }:
let
  hasSecret = name: lib.hasAttrByPath [ "age" "secrets" name ] config;
  secretPath = name: if hasSecret name then config.age.secrets.${name}.path else null;
  gitEmailConfigPath = "${config.xdg.configHome}/git/.gitconfig-email";
  makeGitEmailConfigVariations = website: emailPath: ''
    [includeIf "hasconfig:remote.*.url:https://${website}/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:http://${website}/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:git@${website}:*/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:ssh://git@${website}/**"]
      path = "${emailPath}"

    [includeIf "hasconfig:remote.*.url:ssh://${website}/**"]
      path = "${emailPath}"
  '';
  createGitEmailConfig =
    websiteEmailPairs:
    lib.pipe websiteEmailPairs [
      (lib.attrsets.mapAttrsToList makeGitEmailConfigVariations)
      (builtins.concatStringsSep "\n")
    ];
in
{
  programs.git = {
    signing = {
      format = "ssh";
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
    };

    settings = lib.optionalAttrs (hasSecret "git-allowedSigners") {
      gpg.ssh.allowedSignersFile = secretPath "git-allowedSigners";
    };

    includes =
      (lib.optionals (hasSecret "gitconfig-userName") [ { path = secretPath "gitconfig-userName"; } ])
      ++ (lib.optionals (hasSecret "gitconfig-userEmail") [
        { path = secretPath "gitconfig-userEmail"; }
      ])
      ++ lib.optionals (
        hasSecret "gitconfig-userEmail-GitHub" || hasSecret "gitconfig-userEmail-Cornell"
      ) [ { path = gitEmailConfigPath; } ];
  };

  home.file.${gitEmailConfigPath}.text =
    lib.mkIf (hasSecret "gitconfig-userEmail-GitHub" || hasSecret "gitconfig-userEmail-Cornell")
      (
        createGitEmailConfig (
          (lib.optionalAttrs (hasSecret "gitconfig-userEmail-GitHub") {
            "github.com" = secretPath "gitconfig-userEmail-GitHub";
            "gist.github.com" = secretPath "gitconfig-userEmail-GitHub";
          })
          // (lib.optionalAttrs (hasSecret "gitconfig-userEmail-Cornell") {
            "github.coecis.cornell.edu" = secretPath "gitconfig-userEmail-Cornell";
            "gitlab.cs.cornell.edu" = secretPath "gitconfig-userEmail-Cornell";
          })
        )
      );
}
