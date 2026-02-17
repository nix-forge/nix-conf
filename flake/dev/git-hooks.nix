{ inputs, lib, ... }:
{
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
    {
      pre-commit = {
        settings = {
          package = pkgs.prek;
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              pass_filenames = true;
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
            };
            ruff = {
              enable = true;
              entry = "${lib.getExe pkgs.ruff} check .";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ty = {
              enable = true;
              name = "ty";
              package = pkgs.ty;
              entry = "${lib.getExe pkgs.ty} check";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff" ];
            };

            end-of-file-fixer = {
              enable = true;
              after = [ "treefmt" ];
            };
            trim-trailing-whitespace = {
              enable = true;
              after = [ "treefmt" ];
            };
            mixed-line-endings = {
              enable = true;
              args = [ "--fix=lf" ];
              after = [ "treefmt" ];
            };

            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;

            detect-private-keys.enable = true;

            check-case-conflicts.enable = true;
            check-added-large-files.enable = true;
            check-executables-have-shebangs.enable = true;
            check-shebang-scripts-are-executable.enable = true;
            fix-byte-order-marker.enable = true;

            check-json.enable = true;
            check-toml.enable = true;
            check-yaml.enable = true;

            flake-checker.enable = true;
          };
        };
      };
    };

}
