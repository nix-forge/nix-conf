# Keep native behavior checks after the selected upstream packages gain fixes.
{ pkgs, inputs }:
let
  selected = pkgs.extend (import ../../overlays { inherit inputs; });
  inherit (pkgs) lib;
  ghostty = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
in
{
  nom-upstream-activities = selected.nix-output-monitor.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/nom-upstream-activities-tests.patch ];
    doCheck = true;
  });
  nu-scripts-pytest = pkgs.runCommand "upstream-nu-scripts-pytest" { } ''
    NU_CHECK_FILE=${selected.nu_scripts}/share/nu_scripts/custom-completions/pytest/pytest-completions.nu \
      ${lib.getExe pkgs.nushell} --no-config-file --commands \
      'if not (nu-check --debug $env.NU_CHECK_FILE) { exit 1 }'
    # A concatenated copy exposes the module-private providers in the same scope.
    cat ${selected.nu_scripts}/share/nu_scripts/custom-completions/pytest/pytest-completions.nu > probe.nu
    cat ${./scripts/nu-pytest-choices.nu} >> probe.nu
    ${lib.getExe pkgs.nushell} --no-config-file probe.nu
    touch "$out"
  '';
  ghostty-bash-upstream =
    pkgs.runCommand "upstream-ghostty-bash-prompt" { nativeBuildInputs = [ pkgs.bash ]; }
      ''
        export GHOSTTY_CHECK_SOURCE=${ghostty.shell_integration}/bash/ghostty.bash
        bash --noprofile --norc -i ${./scripts/ghostty-bash-prompt.sh}
        touch "$out"
      '';
}
// lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  nvidia-loader-upstream = pkgs.runCommand "upstream-nvidia-loader" { } ''
    ${pkgs.linuxPackages.nvidiaPackages.production.bin}/bin/nvidia-smi --help > "$out"
  '';
}
