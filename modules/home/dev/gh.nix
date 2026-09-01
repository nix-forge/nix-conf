{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.sessionVariables = {
    # Nix manages both the CLI and its packaged extensions. Suppress checks
    # that cannot safely update the immutable installation.
    GH_NO_EXTENSION_UPDATE_NOTIFIER = "1";
    GH_NO_UPDATE_NOTIFIER = "1";
  };

  programs.gh = {
    enable = true;

    extensions = [ pkgs.gh-poi ];
    settings = {
      aliases = {
        co = "pr checkout";
        pv = "pr view";
      };
      color_labels = "enabled";
      editor = lib.mkIf (config.home.sessionVariables ? EDITOR) config.home.sessionVariables.EDITOR;
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };

  programs.gh-dash.enable = true;
}
