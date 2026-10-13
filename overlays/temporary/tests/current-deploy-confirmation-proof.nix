# Source repair remains isolated until its raw and repaired native controls pass.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  upstream = flake.inputs.deploy-rs.packages.aarch64-darwin.default;
  repairPatch = ../patches/deploy-confirmation-parent-path.patch;
  regressionPatch = ../patches/deploy-confirmation-directory-tests.patch;
  repaired = upstream.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ repairPatch ];
  });
  fullPackage = (import ../deploy-rs-darwin-tests.nix { }).apply repaired;
  diagnostic = (import ./current-deploy-watch-proof.nix).strictDiagnostic;
  withDirectoryTests =
    patches:
    diagnostic.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ patches ++ [ regressionPatch ];
      postCheck = (old.postCheck or "") + ''
        python3 ${./deploy-confirmation-path-result.py} extra \
          "$(cat test-binary-path)" strict-results
      '';
      installPhase = old.installPhase + ''
        cp ${./deploy-confirmation-path-result.py} "$out/path-proof.py"
      '';
    });
in
assert fullPackage.doCheck;
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
    guardAdvanced = false;
    repairPatchSha256 = builtins.hashFile "sha256" repairPatch;
    regressionPatchSha256 = builtins.hashFile "sha256" regressionPatch;
    fullTestsRetainExistingThreeCapabilityExclusions = true;
    hostOriginalThreeAndNormalAliasTestsRequired = true;
  };
  inherit fullPackage;
  rawAliasDiagnostic = withDirectoryTests [ ];
  repairedDiagnostic = withDirectoryTests [ repairPatch ];
}
