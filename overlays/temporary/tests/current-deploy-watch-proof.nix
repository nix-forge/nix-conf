# Diagnostic pair only. This never changes installed Deploy tests or guards.
let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  upstream = flake.inputs.deploy-rs.packages.aarch64-darwin.default;
  export = upstream.overrideAttrs (old: {
    __noChroot = false;
    doCheck = true;
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
    # Compile the unchanged selected test executable; recording is diagnostic.
    checkPhase = ''
      runHook preCheck
      cargo tree --offline --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget} \
        -e features -i notify > notify-features.txt
      python3 - <<'PYFEATURES'
      from pathlib import Path
      features = Path('notify-features.txt').read_text()
      if 'macos_fsevent' not in features or 'macos_kqueue' in features:
          raise ValueError('The selected Notify backend is not the expected FSEvents backend')
      PYFEATURES
      cargo test --offline --release --target ${pkgs.stdenv.hostPlatform.rust.rustcTarget} \
        --bin activate --no-run --message-format=json > test-artifacts.json
      python3 - <<'PY'
      import json
      from pathlib import Path
      candidates = []
      for line in Path('test-artifacts.json').read_text().splitlines():
          record = json.loads(line)
          if record.get('reason') == 'compiler-artifact' and record.get('profile', {}).get('test'):
              if record['target']['name'] == 'activate' and record.get('executable'):
                  candidates.append(record['executable'])
      if len(candidates) != 1:
          raise ValueError('Expected exactly one unchanged activate test binary')
      Path('test-binary-path').write_text(candidates[0])
      PY
      cc -Wall -Wextra -Werror -Wno-deprecated-declarations -framework CoreServices \
        ${./deploy-fsevents-probe.c} -o fsevents-probe
      python3 ${./deploy-watch-pair.py} record "$(cat test-binary-path)" \
        "$PWD/fsevents-probe" strict-results
      runHook postCheck
    '';
    installPhase = ''
      mkdir -p "$out/bin"
      cp "$(cat test-binary-path)" "$out/bin/activate-tests"
      cp fsevents-probe "$out/bin/fsevents-probe"
      cp notify-features.txt "$out/"
      cp -R strict-results "$out/strict"
      cp ${./deploy-watch-pair.py} "$out/compare.py"
    '';
    dontFixup = true;
  });
in
assert !(upstream.__noChroot or false);
{
  metadata = {
    revision = flake.inputs.deploy-rs.rev;
    source = upstream.src.outPath;
    originalPackage = upstream.drvPath;
    strictSandboxRequired = true;
    rawTestsUnmodified = true;
    permissionDenialProven = false;
    hostControlRequired = true;
  };
  strictDiagnostic = export;
}
