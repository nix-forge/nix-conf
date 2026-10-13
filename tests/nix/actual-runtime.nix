# Exercise the installed service and its own native SQLite binding on loopback.
{ pkgs, actualPackage }:
let
  inherit (pkgs) lib;
  node =
    lib.findSingle (dependency: lib.getName dependency == "nodejs")
      (throw "Actual has no selected Node runtime")
      (throw "Actual has multiple selected Node runtimes")
      actualPackage.nativeBuildInputs;
  regression =
    pkgs.runCommand "actual-source-runtime-regression" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${../../overlays/temporary/tests/actual-css-result.py} actual-css-result.py
        cp ${../../overlays/temporary/tests/actual-runtime.py} actual-runtime.py
        cp ${../../overlays/temporary/tests/test_actual_proof.py} test_actual_proof.py
        python3 -m unittest discover -s . -p test_actual_proof.py
        touch "$out"
      '';
  sqlite = pkgs.writeText "actual-packaged-sqlite.mjs" ''
    import { createRequire } from 'node:module';
    import { join } from 'node:path';
    const [root, file] = process.argv.slice(2);
    if (process.versions.node.split('.')[0] !== '${lib.versions.major node.version}') {
      throw new Error('The selected packaged Node runtime version does not match');
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
    pkgs.runCommand "actual-packaged-runtime"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        # Only the isolated service's loopback connections are permitted.
        __noChroot = false;
        __darwinAllowLocalNetworking = true;
      }
      ''
        test -e ${regression}
        mkdir -p "$out"
        data=$(mktemp -d)
        ${node}/bin/node ${sqlite} ${actualPackage}/lib/actual "$data/sqlite-proof.db" > "$out/sqlite.json"
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
        ${actualPackage}/bin/actual-server > "$out/server.log" 2>&1 &
        process=$!
        trap 'kill "$process" 2>/dev/null || true; wait "$process" 2>/dev/null || true' EXIT
        if ! python3 ${../../overlays/temporary/tests/actual-runtime.py} "$port" \
          ${actualPackage}/lib/actual/packages/desktop-client/build ${lib.escapeShellArg actualPackage.version}; then
          cat "$out/server.log"
          exit 1
        fi
        test -s "$ACTUAL_DATA_DIR/server-files/account.sqlite"
        printf '%s\n' 'Installed server and web assets passed; packaged Node SQLite persisted a write.' > "$out/result.txt"
      '';
in
assert !(actualPackage.__noChroot or false);
rawRuntime
