{ lib, pkgs, ... }: {
  reason = "Ghostty 1.3.1 emits duplicate Bash prompt markers with ble.sh.";
  upstream = "https://github.com/ghostty-org/ghostty/pull/11644";
  removal = "The selected Ghostty release includes the merged Bash prompt fix.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  packageName = if pkgs.stdenv.hostPlatform.isDarwin then "ghostty-bin" else "ghostty";
  appliesTo = package: lib.getVersion package == "1.3.1";
  apply =
    package:
    package
    // {
      # A separate integration copy preserves the signed macOS application.
      shell_integration =
        pkgs.runCommandLocal "ghostty-bash-integration"
          {
            nativeBuildInputs = [
              pkgs.patch
              pkgs.bash
            ];
          }
          (
            (import ../../lib/templates/text.nix) ./scripts/patch-ghostty-bash-integration.sh {
              package_shell_integration = package.shell_integration;
              patches_ghostty_bash_ble_prompt_patch = ./patches/ghostty-bash-ble-prompt.patch;
            }
          );
    };
}
