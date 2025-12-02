{
  config,
  pkgs,
  lib,
  ...
}:
{
  programs.gh = {
    enable = true;

    extensions = [
      pkgs.gh-poi # gh poi to delete merged local branches
      pkgs.gh-eco # explore github repos and profiles
      pkgs.gh-copilot # github copilot
    ]
    ++ lib.optionals config.programs.gh-dash.enable [
      config.programs.gh-dash.package
    ];

    settings = {
      editor = config.home.sessionVariables.EDITOR;
      git_protocol = "ssh";
    };
  };

  programs.gh-dash = {
    enable = true;
  };
}
