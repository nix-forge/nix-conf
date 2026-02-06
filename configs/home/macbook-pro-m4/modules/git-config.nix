{ config, lib, ... }:
let
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

    settings = {
      gpg.ssh.allowedSignersFile = config.age.secrets.git-allowedSigners.path;
    };

    includes = [
      { inherit (config.age.secrets.gitconfig-userName) path; }
      { inherit (config.age.secrets.gitconfig-userEmail) path; }

      { path = gitEmailConfigPath; }
    ];
  };

  home.file.${gitEmailConfigPath}.text = createGitEmailConfig {
    "github.com" = config.age.secrets.gitconfig-userEmail-GitHub.path;
    "gist.github.com" = config.age.secrets.gitconfig-userEmail-GitHub.path;

    "github.coecis.cornell.edu" =
      config.age.secrets.gitconfig-userEmail-Cornell.path;
    "gitlab.cs.cornell.edu" = config.age.secrets.gitconfig-userEmail-Cornell.path;
  };
}
