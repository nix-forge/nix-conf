{ inputs, myLib, ... }: {
  perSystem =
    { pkgs, config, ... }:
    let
      portable =
        (import ../../tests/nix/bash-writers.nix { inherit pkgs myLib; })
        // (import ../../tests/nix/non-bash-writers.nix { inherit pkgs inputs myLib; });
      linux = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        (import ../../tests/nix/generated-configs.nix { inherit pkgs inputs myLib; })
        // (import ../../tests/nix/template-configs.nix { inherit pkgs inputs myLib; })
        // (import ../../tests/nix/writer-configs.nix { inherit pkgs myLib; })
      );
      artifactChecks = portable // linux;
      integrationChecks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        removeAttrs (import ../../tests/nix/noogle.nix { inherit pkgs inputs myLib; }) [
          # This boots a VM and remains a separate integration check.
          "service-command-arguments"
        ]
      );
    in
    {
      checks = artifactChecks // {
        generated-artifacts = pkgs.linkFarm "generated-artifact-checks" (
          artifactChecks
          // integrationChecks
          // {
            inherit (config.checks) python-tests;
          }
        );
      };
    };
}
