{ inputs, lib, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem.treefmt = {
    # Preserve captured upstream source, logs, and checksums byte for byte.
    settings.global.excludes = [ "docs/assets/hyprland-upstream-local-20260907/**" ];
    # Keep path-flake checks hermetic in linked worktrees.  treefmt creates a
    # fresh Git repository for its diff check and must not inherit the
    # worktree's external `.git` pointer.
    projectRoot = lib.mkForce (lib.cleanSource inputs.self.outPath);
    programs = {
      # YAML and GitHub Actions
      yamlfmt = {
        settings.formatter.max_line_length = 100;
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
            # Repository YAML uses one document per file.
            document-start = "disable";
            # yamlfmt emits one space before inline comments.
            comments.min-spaces-from-content = 1;
            # GitHub Actions uses the YAML 1.2 key `on`.
            truthy.check-keys = false;
            line-length = {
              max = 160;
              level = "error";
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

      # Rust
      rustfmt.enable = true;

      # Lua
      stylua = {
        enable = true;
        settings = {
          column_width = 100;
          indent_type = "Spaces";
          indent_width = 2;
          line_endings = "Unix";
          quote_style = "AutoPreferDouble";
        };
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
  };
}
