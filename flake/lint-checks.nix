{ self, ... }: {
  # The required Linux lint job owns portable tooling. Native jobs own the
  # remaining checks; additions within either tool configuration follow it.
  flake.lintChecks = builtins.mapAttrs (_: checks: {
    inherit (checks) pre-commit treefmt;
  }) self.checks;
}
