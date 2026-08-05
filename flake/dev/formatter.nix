{ inputs, ... }: {
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
    yamllint = {
      enable = true;
      priority = 300;
      settings = {
        extends = "default";
        rules = {
          document-start = "disable";
          line-length = {
            max = 160;
            level = "warning";
          };
        };
      };
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
    nixf-diagnose = {
      enable = true;
      autoFix = false;
      priority = 400;
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
    taplo.enable = true;
    rumdl-check.enable = true;
    typos = {
      enable = true;
      configFile = ".typos.toml";
    };
    prettier = {
      enable = true;
      excludes = [
        "*.md"
        "*.yaml"
        "*.yml"
      ];
      settings.proseWrap = "always";
    };
  };
}
