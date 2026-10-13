# Native proof packages never advance installed temporary-fix review guards.
let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  system = "aarch64-darwin";
  pkgs = import flake.inputs.nixpkgs {
    inherit system;
    config.allowUnfreePredicate = package: lib.getName package == "claude-code";
  };
  inherit (pkgs) lib;
  functionalGate =
    package:
    lib.findSingle (check: lib.getName check == "nix-functional-tests")
      (throw "No Determinate functional gate")
      (throw "Multiple Determinate functional gates")
      package.buildInputs;
  unitGates =
    package: builtins.filter (check: lib.getName check != "nix-functional-tests") package.buildInputs;
  upstream = flake.inputs.determinate.inputs.nix.packages.${system}.default;
  functional = functionalGate upstream;
  repaired = (import ../determinate-darwin-tests.nix { inherit lib; }).apply upstream;
  repairedFunctional = functionalGate repaired;
  checker = ./darwin-package-result.py;
  regression =
    pkgs.runCommand "darwin-package-result-regression" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${checker} darwin-package-result.py
        cp ${./test_darwin_package_result.py} test_darwin_package_result.py
        python3 -m unittest discover -s . -p test_darwin_package_result.py
        touch "$out"
      '';
  rawSentryDenied = functional.overrideAttrs (old: {
    __noChroot = false;
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    checkPhase = ''
      runHook preCheck
      test -e ${regression}
      meson --version
      meson introspect --tests > registered-tests.json
      status=0
      meson test --no-rebuild --print-errorlogs --logbase=sentry-baseline sentry || status=$?
      ${lib.getExe pkgs.python3} ${checker} sentry meson-logs/sentry-baseline.json --status "$status"
      runHook postCheck
    '';
    installPhase = ''
      mkdir -p "$out"
      cp meson-logs/sentry-baseline.{json,txt} registered-tests.json "$out/"
    '';
  });
  checkedFunctional = repairedFunctional.overrideAttrs (old: {
    postCheck = (old.postCheck or "") + ''
      test -e ${regression}
      meson introspect --tests > registered-tests.json
      ${lib.getExe pkgs.python3} ${checker} registration \
        ${rawSentryDenied}/registered-tests.json --repaired registered-tests.json
    '';
    installPhase = (old.installPhase or "") + ''
      cp registered-tests.json "$out/"
    '';
  });
  checkedPackage = repaired.override { nix-functional-tests = checkedFunctional; };
  nh = (import ../nh-darwin-home.nix { inherit lib; }).apply pkgs.nh-unwrapped;
  nhWithRegression = nh.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    postCheck = (old.postCheck or "") + ''
      test -e ${regression}
      CARGO_TERM_COLOR=never cargo test --offline --release \
        --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget} -p nh-core \
        command::tests::test_elevated_darwin_home_is_absolute -- --exact > absolute-home.log 2>&1
      cat absolute-home.log
      ${lib.getExe pkgs.python3} ${checker} home absolute-home.log
    '';
  });
  claudeUpstream = pkgs.claude-code;
  claude = (import ../claude-code-sandbox.nix { }).apply claudeUpstream;
  deployUpstream = flake.inputs.deploy-rs.packages.${system}.default;
  deploy = (import ../deploy-rs-darwin-tests.nix { }).apply deployUpstream;
  deployWithTests = deploy.overrideAttrs (old: {
    doCheck = true;
    postCheck = (old.postCheck or "") + ''
      test -e ${regression}
      # These non-watcher sentinel cases must remain live.
      CARGO_TERM_COLOR=never cargo test --offline --release --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget} \
        --bin activate tests::wait_cancelled_when_cancel_file_already_exists -- --exact > sentinel-existing.log 2>&1
      cat sentinel-existing.log
      ${lib.getExe pkgs.python3} ${checker} sentinel-existing sentinel-existing.log
      CARGO_TERM_COLOR=never cargo test --offline --release --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget} \
        --bin activate tests::remove_activation_cancel_clears_the_sentinel -- --exact > sentinel-removal.log 2>&1
      cat sentinel-removal.log
      ${lib.getExe pkgs.python3} ${checker} sentinel-removal sentinel-removal.log
    '';
  });
  deployRawWatcherDenied = deployUpstream.overrideAttrs (old: {
    __noChroot = false;
    doCheck = true;
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    checkPhase = ''
      runHook preCheck
      test -e ${regression}
      status=0
      CARGO_TERM_COLOR=never cargo test --offline --release \
        --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget} --bin activate \
        tests::confirmation_watcher_observes_immediate_canary_removal \
        -- --exact > watcher-baseline.log 2>&1 || status=$?
      cat watcher-baseline.log
      ${lib.getExe pkgs.python3} ${checker} deploy watcher-baseline.log --status "$status"
      runHook postCheck
    '';
    installPhase = ''
      mkdir -p "$out"
      cp watcher-baseline.log "$out/"
    '';
    dontFixup = true;
  });
in
assert import ./darwin-functional-contract.nix;
assert upstream.doCheck && functional.doCheck && repaired.doCheck && repairedFunctional.doCheck;
assert builtins.length upstream.buildInputs == 6 && builtins.length repaired.buildInputs == 6;
assert builtins.length (unitGates upstream) == 5;
assert !(repaired.__noChroot or false) && !(repairedFunctional.__noChroot or false);
assert
  map (gate: gate.drvPath) (unitGates upstream) == map (gate: gate.drvPath) (unitGates repaired);
assert repairedFunctional.mesonCheckFlags == functional.mesonCheckFlags;
assert
  repairedFunctional.patches
  == (functional.patches or [ ]) ++ [ ../patches/determinate-darwin-sentry-registration.patch ];
assert checkedPackage.doCheck && checkedFunctional.doCheck;
assert builtins.length checkedPackage.buildInputs == 6;
assert
  map (gate: gate.drvPath) (unitGates upstream)
  == map (gate: gate.drvPath) (unitGates checkedPackage);
assert nh.version == "4.4.2" && nhWithRegression.doCheck;
assert nhWithRegression.checkFlags == pkgs.nh-unwrapped.checkFlags;
assert claude.__noChroot == false && claude.doInstallCheck == false;
assert claude.src.outputHash == claudeUpstream.src.outputHash;
assert deployWithTests.doCheck;
assert
  deploy.checkFlags == (deployUpstream.checkFlags or [ ])
  ++ [
    "--skip=tests::confirmation_watcher_observes_immediate_canary_removal"
    "--skip=tests::wait_cancelled_when_cancel_file_created_while_waiting"
    "--skip=tests::wait_returns_when_canary_created_while_waiting"
  ];
{
  metadata = {
    requiredSandbox = true;
    combinedStrictSandbox = !(repaired.__noChroot or false);
    functionalStrictSandbox = !(repairedFunctional.__noChroot or false);
    functionalLocalNetworking = repairedFunctional.__darwinAllowLocalNetworking;
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    nixRevision = flake.inputs.determinate.inputs.nix.rev;
    nixVersion = upstream.version;
    functionalGate = functional.drvPath;
    functionalMesonVersions = lib.unique (
      map (tool: tool.version) (
        builtins.filter (tool: lib.getName tool == "meson") functional.nativeBuildInputs
      )
    );
    repairedFunctionalGate = repairedFunctional.drvPath;
    nativeCheckedFunctionalGate = checkedFunctional.drvPath;
    nativeCheckedCombinedGate = checkedPackage.drvPath;
    unitGateNames = map lib.getName (unitGates upstream);
    unitGatesPreserved =
      map (gate: gate.drvPath) (unitGates upstream) == map (gate: gate.drvPath) (unitGates repaired);
    repairedFunctionalFlags = repairedFunctional.mesonCheckFlags;
    nhVersion = nh.version;
    nhSourceHash = nh.src.outputHash;
    nhChecksEnabled = nhWithRegression.doCheck;
    claudeVersion = claude.version;
    claudeSourceHash = claude.src.outputHash;
    claudeStrictSandbox = !claude.__noChroot;
    claudeInstallCheckDisabled = !claude.doInstallCheck;
    deployRevision = flake.inputs.deploy-rs.rev;
    deployCheckFlags = deployWithTests.checkFlags;
    deployChecksEnabled = deployWithTests.doCheck;
  };
  determinate = checkedPackage;
  determinateFunctional = checkedFunctional;
  nh = nhWithRegression;
  deploy = deployWithTests;
  inherit
    rawSentryDenied
    claude
    deployRawWatcherDenied
    regression
    ;
}
