{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { config, ... }:
    {
      # provide the formatter for `nix fmt`
      formatter = config.treefmt.build.wrapper;

      # configure treefmt
      treefmt = {
        projectRootFile = "flake.nix";
        enableDefaultExcludes = true;

        settings = {
          global.excludes = [ "*.age" ];
        };

        programs = {
          # GitHub Actions
          actionlint = {
            enable = true;
            # Run after general YAML formatting to reduce churn
            priority = 300;
          };

          # Nix formatters and fixers
          # Run deadnix -> statix -> nixfmt
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
            strict = true;
            priority = 300;
          };

          # Shell: format then lint
          shfmt = {
            enable = true;
            indent_size = 2; # set to 0 to use tabs
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
          yamlfmt.enable = true;
        };
      };
    };
}
