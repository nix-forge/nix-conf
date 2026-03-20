{ config, lib, ... }:
(lib.optionalAttrs (lib.hasAttrByPath [ "age" "secrets" "gitconfig-userEmail-GitHub" ] config) {
  "github.com" = config.age.secrets.gitconfig-userEmail-GitHub.path;
  "gist.github.com" = config.age.secrets.gitconfig-userEmail-GitHub.path;
})
// (lib.optionalAttrs (lib.hasAttrByPath [ "age" "secrets" "gitconfig-userEmail-Cornell" ] config) {
  "github.coecis.cornell.edu" = config.age.secrets.gitconfig-userEmail-Cornell.path;
  "gitlab.cs.cornell.edu" = config.age.secrets.gitconfig-userEmail-Cornell.path;
})
