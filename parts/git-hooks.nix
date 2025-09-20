{ self, ... }:
{
  flake = {
    git-hooks.hooks = {
      nixfmt-rfc-style.enable = true;
      statix.enable = true; # static analysis for common pitfalls
      deadnix.enable = true; # finds unused let bindings, etc.

      nil.enable = true; # Nix language server checks

      # Secrets & hygiene
      ripsecrets.enable = true;
      end-of-file-fixer.enable = true;
      trim-trailing-whitespace.enable = true;
      mixed-line-endings.enable = true;
      check-merge-conflicts.enable = true;
      check-symlinks.enable = true;

      # Markdown/YAML
      markdownlint.enable = true;
      yamllint.enable = true;

      # Optional: disallow direct commits to main
      # no-commit-to-branch.settings.branch = [ "main" "master" ];
      # no-commit-to-branch.enable = true;
    };
  };

  perSystem =
    { system, ... }:
    {

      checks.pre-commit-check = self.inputs.git-hooks.lib.${system}.run {
        src = ./.;
        inherit (self.git-hooks) hooks;
      };
    };
}
