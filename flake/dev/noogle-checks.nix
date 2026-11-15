{ configurationInputs, myLib, ... }: {
  perSystem = { pkgs, configurationPkgs, ... }: {
    checks = {
      local-feature-reuse = import ../../tests/nix/local-feature-reuse.nix {
        pkgs = configurationPkgs;
        inputs = configurationInputs;
        inherit myLib;
      };
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
      {
        iwd-runtime-profiles = import ../../tests/nix/iwd-runtime-profiles.nix {
          pkgs = configurationPkgs;
          inputs = configurationInputs;
          inherit myLib;
        };
        module-independence = import ../../tests/nix/module-independence.nix {
          pkgs = configurationPkgs;
          inputs = configurationInputs;
          inherit myLib;
        };
      }
      // import ../../tests/nix/noogle.nix {
        pkgs = configurationPkgs;
        inputs = configurationInputs;
        inherit myLib;
      }
    );
  };
}
