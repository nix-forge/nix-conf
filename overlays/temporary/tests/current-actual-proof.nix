# Build/runtime evidence against current inputs, without accepting their guards.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  inherit (pkgs) lib;
  upstream = pkgs.actual-server;
  improved = (import ../actual-server-case.nix { }).apply upstream;
  fifthCopy = "  packages/component-library/src/themes~nix~case~hack~1/sidebar-redesign-light.css \\\n";
  fifthRewrite = " \\\n  --replace-fail \"@actual-app/components/themes/sidebar-redesign-light.css?inline\" \"./themes/sidebar-redesign-light.css?inline\"";
  current = improved.overrideAttrs {
    postPatch = builtins.replaceStrings [ fifthCopy fifthRewrite ] [ "" "" ] improved.postPatch;
  };
  node = pkgs.nodejs_24;
  checker = ./actual-css-result.py;
  regression =
    pkgs.runCommand "actual-proof-classifier-regression" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${checker} actual-css-result.py
        cp ${./actual-runtime.py} actual-runtime.py
        cp ${./test_actual_proof.py} test_actual_proof.py
        python3 -m unittest discover -s . -p test_actual_proof.py
        touch "$out"
      '';
  cssFailure =
    package: mode:
    package.overrideAttrs (old: {
      pname = "actual-${mode}-css-failure-evidence";
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
      buildPhase = ''
        test -e ${regression}
        test -d packages/component-library/src/themes~nix~case~hack~1
        status=0
        # A new Bash process preserves errexit even while its failure is captured.
        bash -e -o pipefail ${pkgs.writeText "actual-${mode}-build-phase.sh" ''
          source "$stdenv/setup"
          ${old.buildPhase}
        ''} > actual-build.log 2>&1 || status=$?
        cat actual-build.log
        ${lib.getExe pkgs.python3} ${checker} ${mode} "$status" actual-build.log
      '';
      installPhase = ''
        mkdir -p "$out"
        cp actual-build.log "$out/"
      '';
      # This output contains an expected failure log, never an installed server.
      dontFixup = true;
    });
  sqlite = pkgs.writeText "actual-packaged-sqlite.mjs" ''
    import { createRequire } from 'node:module';
    import { join } from 'node:path';
    const [root, file] = process.argv.slice(2);
    if (process.versions.node.split('.')[0] !== '24') {
      throw new Error('The selected packaged runtime is not Node24');
    }
    const require = createRequire(join(root, 'packages/sync-server/package.json'));
    const Database = require('better-sqlite3');
    let database = new Database(file);
    database.exec('CREATE TABLE proof (value TEXT NOT NULL)');
    database.prepare('INSERT INTO proof(value) VALUES (?)').run('native-roundtrip');
    database.close();
    database = new Database(file);
    if (database.prepare('SELECT value FROM proof').get().value !== 'native-roundtrip') {
      throw new Error('Packaged native SQLite did not persist its write');
    }
    console.log(JSON.stringify({node: process.versions.node, abi: process.versions.modules,
      sqlite: database.prepare('SELECT sqlite_version() AS version').get().version}));
    database.close();
  '';
  runtime =
    pkgs.runCommand "actual-packaged-runtime-proof"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        # Match the upstream package's scoped Darwin loopback allowance.
        __darwinAllowLocalNetworking = true;
      }
      ''
        test -e ${regression}
        mkdir -p "$out"
        data=$(mktemp -d)
        ${node}/bin/node ${sqlite} ${improved}/lib/actual "$data/sqlite-proof.db" > "$out/sqlite.json"
        port=$(python3 - <<'PYPORT'
        import socket
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            print(listener.getsockname()[1])
        PYPORT
        )
        export NODE_ENV=production ACTUAL_DATA_DIR="$data/server-data"
        export ACTUAL_PORT="$port" ACTUAL_HOSTNAME=127.0.0.1
        mkdir -p "$ACTUAL_DATA_DIR"
        ${improved}/bin/actual-server > "$out/server.log" 2>&1 &
        process=$!
        trap 'kill "$process" 2>/dev/null || true; wait "$process" 2>/dev/null || true' EXIT
        if ! python3 ${./actual-runtime.py} "$port" \
          ${improved}/lib/actual/packages/desktop-client/build ${lib.escapeShellArg improved.version}; then
          cat "$out/server.log"
          exit 1
        fi
        test -s "$ACTUAL_DATA_DIR/server-files/account.sqlite"
        printf '%s\n' 'Installed server and web assets passed; packaged Node24 SQLite persisted a write.' > "$out/result.txt"
      '';
in
assert current.drvPath != improved.drvPath;
assert current.version == upstream.version && improved.version == upstream.version;
assert lib.hasInfix fifthCopy improved.postPatch;
assert lib.hasInfix fifthRewrite improved.postPatch;
assert builtins.any (dependency: dependency.drvPath == node.drvPath) upstream.nativeBuildInputs;
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    actualVersion = upstream.version;
    nodeVersion = node.version;
    upstreamPackage = upstream.drvPath;
    currentPackage = current.drvPath;
    improvedPackage = improved.drvPath;
    localNetworking = upstream.__darwinAllowLocalNetworking;
  };
  upstreamCssFailure = cssFailure upstream "raw";
  currentCssFailure = cssFailure current "four";
  improvedPackage = improved;
  inherit runtime regression;
}
