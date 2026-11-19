{ self, ... }: {
  # The required Linux lint job owns portable tooling. Native jobs own the
  # remaining checks; additions within either tool configuration follow it.
  # Rust package and quality checks retain their native platform selection.
  flake.lintChecks = builtins.mapAttrs (_: checks: {
    inherit (checks)
      pre-commit
      runtime-source-policy
      javascript-quality
      stylesheet-quality
      swift-quality
      lua-quality
      treefmt
      documentation
      ;
  }

  ) self.checks;
  # Hosted CI runs this check before native work. Keep the complete lintChecks
  # inventory for local consumers and native-check exclusions. The lint job
  # runs the same generated all-file hooks in devShells.ci, plus publication
  # history scanning; rebuilding the isolated pre-commit check adds no scope.
  flake.hostedLintChecks = builtins.mapAttrs (
    _: checks: removeAttrs checks [ "pre-commit" ]
  ) self.lintChecks;

  flake.ciChecks = builtins.mapAttrs (
    system: checks: removeAttrs checks (builtins.attrNames (self.lintChecks.${system} or { }))
  ) self.checks;
}
