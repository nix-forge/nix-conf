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
          # Keep secrets and common caches/outputs out of the formatter
          global.excludes = [
            "*.age"
            # General dev caches
            ".git/**"
            ".direnv/**"
            "result/**"
            "node_modules/**"
            # Python-specific caches and virtual envs
            ".mypy_cache/**"
            ".ruff_cache/**"
            "__pycache__/**"
            "venv/**"
            ".venv/**"
          ];

          formatter."shfmt" = {
            command = "${pkgs.shfmt}/bin/shfmt";
            options = [
              "--indent"
              "0"
              "--binary-next-line"
              "--case-indent"
              "--space-redirects"
              "--keep-padding"
              "--simplify"
              "--write"
            ];
            includes = [
              "*.sh"
              "*.bash"
              "*.envrc"
              "*.envrc.*"
            ];
            priority = 100;
          };
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

          # Python
          # Order: ruff-check (autofix) -> ruff-format -> mypy (type-check)
          ruff-check = {
            enable = true;
            # Run early to apply autofixes
            priority = 110;
          };
          ruff-format = {
            enable = true;
            # Format after fixes for stable output
            priority = 120;
          };
          mypy = {
            enable = true;
          };

          # Shell: format then lint
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
