{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.jujutsu = {
    enable = true;
    package = pkgs.jujutsu;
    ediff = false;

    settings = {
      aliases.st = {
        definition = [ "status" ];
        doc = "Show working-copy status";
      };

      ui = {
        color = "auto";
        conflict-marker-style = "git";
      }
      // lib.optionalAttrs (config.home.sessionVariables ? EDITOR) {
        editor = config.home.sessionVariables.EDITOR;
      };

      # Keep merges and EOL handling compatible with the shared Git policy.
      merge.hunk-level = "line";
      working-copy.eol-conversion = "input";

      # This refuses to push marked work and any descendant. It is not a
      # substitute for removing a secret that has entered a commit.
      git.private-commits = "description('wip:*') | description('private:*')";
    };
  };

  # Delta owns jj's pager, Git-format diff formatter, and Delta exit handling.
  programs.delta.enableJujutsuIntegration = true;
}
