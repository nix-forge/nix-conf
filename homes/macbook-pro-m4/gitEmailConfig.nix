{ config, ... }:
{
  "github.com" = config.age.secrets.gitconfig-userEmail-GitHub.path;
  "gist.github.com" = config.age.secrets.gitconfig-userEmail-GitHub.path;

  "github.coecis.cornell.edu" = config.age.secrets.gitconfig-userEmail-Cornell.path;
  "gitlab.cs.cornell.edu" = config.age.secrets.gitconfig-userEmail-Cornell.path;
}
