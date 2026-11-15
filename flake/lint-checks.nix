{ self, lib, ... }: {
  # The required Linux lint job owns portable tooling. Native jobs own the
  # remaining checks; additions within either tool configuration follow it.
  # Python analysis targets all platforms through pyproject.toml.
  flake.lintChecks = builtins.mapAttrs (
    _: checks:
    {
      inherit (checks)
        pre-commit
        python-quality
        javascript-quality
        stylesheet-quality
        swift-quality
        lua-quality
        treefmt
        documentation
        gitleaks-policy
        ;
    }
    // lib.optionalAttrs (checks ? dart-quality) { inherit (checks) dart-quality; }
  ) self.checks;
  # Hosted CI runs this check before native work. Keep the complete lintChecks
  # inventory for local consumers and native-check exclusions. The lint job
  # runs the same generated all-file hooks in devShells.ci, plus publication
  # history scanning; rebuilding the isolated pre-commit check adds no scope.
  flake.hostedLintChecks = builtins.mapAttrs (
    _: checks:
    removeAttrs checks [
      "python-quality"
      "pre-commit"
    ]
  ) self.lintChecks;
}
