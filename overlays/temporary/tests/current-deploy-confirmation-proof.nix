# Source repair remains isolated until its raw and repaired native controls pass.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  upstream = flake.inputs.deploy-rs.packages.aarch64-darwin.default;
  repairPatch = builtins.path {
    path = ../patches/deploy-confirmation-parent-path.patch;
    name = "deploy-confirmation-parent-path.patch";
  };
  regressionPatch = builtins.path {
    path = ../patches/deploy-confirmation-directory-tests.patch;
    name = "deploy-confirmation-directory-tests.patch";
  };
  # The owning integration installs this patch once before building this proof.
  installedFix = import ../deploy-rs-darwin-tests.nix { };
  fullPackage = installedFix.apply upstream;
  diagnostic = (import ./current-deploy-watch-proof.nix).strictDiagnostic;
  regression =
    pkgs.runCommand "deploy-confirmation-path-result-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${./deploy-confirmation-path-result.py} deploy-confirmation-path-result.py
        cp ${./test_deploy_confirmation_path_result.py} test_deploy_confirmation_path_result.py
        python3 -m unittest discover -s . -p test_deploy_confirmation_path_result.py
        touch "$out"
      '';
  withDirectoryTests =
    patches:
    diagnostic.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ patches ++ [ regressionPatch ];
      postCheck = (old.postCheck or "") + ''
        test -e ${regression}
        python3 ${./deploy-confirmation-path-result.py} extra \
          "$(cat test-binary-path)" strict-results
      '';
      installPhase = old.installPhase + ''
        cp ${./deploy-confirmation-path-result.py} "$out/path-proof.py"
      '';
    });
in
assert fullPackage.doCheck;
assert fullPackage.patches == (upstream.patches or [ ]) ++ [ repairPatch ];
assert
  fullPackage.checkFlags == (upstream.checkFlags or [ ])
  ++ [
    "--skip=tests::confirmation_watcher_observes_immediate_canary_removal"
    "--skip=tests::wait_cancelled_when_cancel_file_created_while_waiting"
    "--skip=tests::wait_returns_when_canary_created_while_waiting"
  ];
assert !(fullPackage.__noChroot or false);
{
  metadata = {
    revision = flake.inputs.deploy-rs.rev;
    rawPackage = upstream.drvPath;
    repairedPackage = fullPackage.drvPath;
    strictSandboxRequired = true;
    installedGuardMatchesInput = installedFix.reviewedRevision == flake.inputs.deploy-rs.rev;
    proofChangesInstalledGuard = false;
    repairPatchSha256 = builtins.hashFile "sha256" repairPatch;
    regressionPatchSha256 = builtins.hashFile "sha256" regressionPatch;
    fullTestsRetainExistingThreeCapabilityExclusions = true;
    hostOriginalThreeAndNormalAliasTestsRequired = true;
  };
  inherit fullPackage regression;
  rawAliasDiagnostic = withDirectoryTests [ ];
  repairedDiagnostic = withDirectoryTests [ repairPatch ];
}
