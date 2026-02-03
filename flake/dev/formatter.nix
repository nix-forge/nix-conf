{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem.treefmt.programs = {
    # YAML and GitHub Actions
    yamlfmt = {
      enable = true;
      priority = 100;
    };
    actionlint = {
      enable = true;
      priority = 200;
    };

    # Nix
    deadnix = {
      enable = true;
      priority = 100;
    };
    statix = {
      enable = true;
      priority = 200;
    };
    nixfmt = {
      enable = true;
      width = 100;
      strict = true;
      priority = 300;
    };

    # Shell
    shfmt = {
      enable = true;
      indent_size = 2;
      simplify = true;
      priority = 100;
    };
    shellcheck = {
      enable = true;
      priority = 200;
    };

    # Other
    keep-sorted.enable = true;
    just.enable = true;
    prettier = {
      enable = true;
      settings.proseWrap = "always";
    };
  };
}
