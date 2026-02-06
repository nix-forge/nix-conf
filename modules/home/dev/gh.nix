{ config, lib, pkgs, ... }:
{
  programs.gh = {
    enable = true;

    extensions = [ pkgs.gh-poi ];
    settings = {
      editor = lib.mkIf (
        config.home.sessionVariables ? EDITOR
      ) config.home.sessionVariables.EDITOR;
      git_protocol = "ssh";
    };
  };

  programs.gh-dash.enable = true;
}
