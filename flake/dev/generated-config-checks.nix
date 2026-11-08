{
  inputs,
  configurationInputs,
  myLib,
  ...
}:
{
  perSystem =
    {
      pkgs,
      configurationPkgs,
      config,
      ...
    }:
    let
      portable =
        (import ../../tests/nix/bash-writers.nix { inherit pkgs myLib; })
        // (import ../../tests/nix/non-bash-writers.nix { inherit pkgs inputs myLib; })
        // {
          vscode-shell-integration = import ../../tests/nix/vscode-shell-integration.nix {
            inherit pkgs inputs;
          };
          codex-home = import ../../tests/nix/codex-home.nix { inherit pkgs inputs myLib; };
          activation-conflicts = import ../../tests/nix/activation-conflicts.nix {
            inherit pkgs inputs myLib;
          };
          text-rendering = import ../../tests/nix/text-rendering.nix { inherit pkgs; };
          tmux-config = import ../../tests/nix/tmux-config.nix { inherit pkgs inputs; };
        };
      linux = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        (import ../../tests/nix/generated-configs.nix { inherit pkgs inputs myLib; })
        // (import ../../tests/nix/template-configs.nix {
          pkgs = configurationPkgs;
          inputs = configurationInputs;
          inherit myLib;
        })
        // (import ../../tests/nix/writer-configs.nix { inherit pkgs myLib; })
      );
      darwin = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        helium-startup = import ../../tests/nix/helium-startup.nix { inherit pkgs inputs myLib; };
      };
      artifactChecks = portable // linux // darwin;
      integrationChecks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        removeAttrs
          (import ../../tests/nix/noogle.nix {
            pkgs = configurationPkgs;
            inputs = configurationInputs;
            inherit myLib;
          })
          [
            # This boots a VM and remains a separate integration check.
            "service-command-arguments"
          ]
      );
    in
    {
      checks = artifactChecks // {
        generated-artifacts = pkgs.linkFarm "generated-artifact-checks" (
          artifactChecks // integrationChecks // { inherit (config.checks) python-tests; }
        );
      };
    };
}
