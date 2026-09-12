{ self, ... }: {
  # The required Linux lint job owns portable tooling. Native jobs own the
  # remaining checks; additions within either tool configuration follow it.
  # Python analysis targets all platforms through pyproject.toml.
  flake.lintChecks = builtins.mapAttrs (_: checks: {
    inherit (checks)
      pre-commit
      python-quality
      javascript-quality
      treefmt
      documentation
      ;
  }) self.checks;
}
