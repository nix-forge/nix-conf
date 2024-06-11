{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    {
      inputs',
      config,
      pkgs,
      ...
    }:
    let
      lib = inputs'.nixpkgs.lib;
    in
    {
      # provide the formatter for `nix fmt`
      formatter = config.treefmt.build.wrapper;

      # configure treefmt
      treefmt = {
        projectRootFile = "flake.nix";

        programs = {
          nixfmt-rfc-style = {
            enable = true;
            package = pkgs.nixfmt-rfc-style;
          };

          shellcheck.enable = true; # cannot be configured, errors on basic bash convention

          prettier = {
            enable = true;
            package = pkgs.prettierd;
            excludes = [ "*.age" ];
            settings = {
              editorconfig = true;
            };
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
