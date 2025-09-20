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
          actionlint.enable = true;

          deadnix.enable = true;

          keep-sorted.enable = true;

          nixfmt = {
            enable = true;
            strict = true;
          };

          shellcheck.enable = true;

          shfmt = {
            enable = true;
            indent_size = 2; # set to 0 to use tabs
          };

          statix.enable = true;

          just.enable = true;
        };
      };
    };
}
