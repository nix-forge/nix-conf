{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
    {
      # provide the formatter for `nix fmt`
      formatter = config.treefmt.build.wrapper;

      # configure treefmt
      treefmt = {
        projectRootFile = "flake.nix";
        enableDefaultExcludes = true;

        settings = {
          global.excludes = [
            "*.age"
            "*.envrc"
          ];
        };

        programs = {
          nixfmt = {
            enable = true;
            package = pkgs.nixfmt;

            strict = true;
          };

          shellcheck.enable = true; # cannot be configured, errors on basic bash convention

          prettier = {
            enable = true;
            package = pkgs.prettierd;
          };

          shfmt = {
            enable = true;
            # https://flake.parts/options/treefmt-nix.html#opt-perSystem.treefmt.programs.shfmt.indent_size
            indent_size = 2; # set to 0 to use tabs
          };
        };
      };
    };
}
