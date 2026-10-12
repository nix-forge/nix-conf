# Verify the ordinary current package before retiring its installed workaround.
# Actual 26.10 removed the uppercase Themes directory present beside themes in Actual 26.9.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  inherit (pkgs) lib;
  upstream = pkgs.actual-server;
  node = pkgs.nodejs_24;
  regression =
    pkgs.runCommand "actual-source-runtime-regression" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${./actual-css-result.py} actual-css-result.py
        cp ${./actual-runtime.py} actual-runtime.py
        cp ${./test_actual_proof.py} test_actual_proof.py
        python3 -m unittest discover -s . -p test_actual_proof.py
        touch "$out"
      '';
  sourceLayout =
    pkgs.runCommand "actual-selected-source-layout" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        test -e ${regression}
        python3 ${./actual-css-result.py} ${upstream.src} > "$out"
        cat "$out"
      '';
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
  rawRuntime =
    pkgs.runCommand "actual-raw-packaged-runtime-proof"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        # Match the upstream package's scoped Darwin loopback allowance.
        __darwinAllowLocalNetworking = true;
      }
      ''
        test -e ${regression}
        mkdir -p "$out"
        data=$(mktemp -d)
        ${node}/bin/node ${sqlite} ${upstream}/lib/actual "$data/sqlite-proof.db" > "$out/sqlite.json"
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
        ${upstream}/bin/actual-server > "$out/server.log" 2>&1 &
        process=$!
        trap 'kill "$process" 2>/dev/null || true; wait "$process" 2>/dev/null || true' EXIT
        if ! python3 ${./actual-runtime.py} "$port" \
          ${upstream}/lib/actual/packages/desktop-client/build ${lib.escapeShellArg upstream.version}; then
          cat "$out/server.log"
          exit 1
        fi
        test -s "$ACTUAL_DATA_DIR/server-files/account.sqlite"
        printf '%s\n' 'Installed server and web assets passed; packaged Node24 SQLite persisted a write.' > "$out/result.txt"
      '';
in
assert builtins.any (dependency: dependency.drvPath == node.drvPath) upstream.nativeBuildInputs;
assert !(upstream.__noChroot or false);
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    actualVersion = upstream.version;
    nodeVersion = node.version;
    sourceHash = upstream.src.outputHash;
    rawPackage = upstream.drvPath;
    requiredSandbox = true;
    localNetworking = upstream.__darwinAllowLocalNetworking;
    appliesAnyWorkaround = false;
    usesControlledLayout = false;
  };
  rawPackage = upstream;
  inherit rawRuntime sourceLayout regression;
}
