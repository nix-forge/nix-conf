# Native evidence only. These outputs never refresh installed review guards.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  inherit (pkgs) lib;
  upstream = pkgs.prismlauncher-unwrapped;
  improved = (import ../prismlauncher-darwin-tests.nix { }).apply upstream;
  current = upstream.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (pkgs.writeText "prism-current-watch.patch" (
        builtins.replaceStrings
          [
            "@@ -154,6 +155,14 @@"
            "+        QVERIFY(tmp.isValid());\n+        QVERIFY(QDir(tmp.path()).exists());\n"
          ]
          [ "@@ -154,6 +155,12 @@" "" ]
          (builtins.readFile ../patches/prismlauncher-watch-test-capability.patch)
      ))
    ];
  });
  prerequisite = pkgs.writeText "prism-watch-prerequisite.cpp" ''
    #include <QCoreApplication>
    #include <QDir>
    #include <QFileSystemWatcher>
    #include <QTemporaryDir>
    #include <cstdio>
    int main(int argc, char **argv) {
      QCoreApplication application(argc, argv);
      QTemporaryDir directory;
      if (!directory.isValid() || !QDir(directory.path()).exists()) {
        std::fprintf(stderr, "Invalid temporary directory\n");
        return 2;
      }
      QFileSystemWatcher watcher;
      if (!watcher.addPath(directory.path())) {
        std::puts("Native filesystem notifications are unavailable");
        return 3;
      }
      std::puts("Native filesystem notifications are available");
      return 0;
    }
  '';
  checker = ./prism-watch-result.py;
  checkerRegression =
    pkgs.runCommand "prism-watch-classifier-regression" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${checker} prism-watch-result.py
        cp ${./test_prism_watch_result.py} test_prism_watch_result.py
        python3 -m unittest discover -s . -p test_prism_watch_result.py
        touch "$out"
      '';
  proof =
    package: mode:
    package.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
      checkPhase = ''
        runHook preCheck
        test -e ${checkerRegression}
        $CXX -std=c++17 ${prerequisite} -o watch-prerequisite \
          $(pkg-config --cflags --libs Qt6Core)
        capability=0
        ./watch-prerequisite || capability=$?
        case "$capability" in
          0) expected=present ;;
          3) expected=${mode} ;;
          *) printf 'Unexpected watcher prerequisite exit: %s\n' "$capability" >&2; exit 1 ;;
        esac
        printf 'Measured watcher capability exit: %s; required native outcome: %s\n' "$capability" "$expected"
        export QT_QPA_PLATFORM=offscreen
        # Every other CTest target must pass, even for the negative baseline.
        ctest --output-on-failure --exclude-regex '^ResourceFolderModel$'
        status=0
        ./ResourceFolderModel -o prism-watch.xml,xml || status=$?
        if [ "$expected" = unavailable ]; then
          test "$status" = 1
        else
          test "$status" = 0
        fi
        ${lib.getExe pkgs.python3} ${checker} "$expected" prism-watch.xml
        cat prism-watch.xml
        runHook postCheck
      '';
      # Upstream test resources deliberately include invalid .jar fixtures.
      # Export them after ordinary archive normalization, leaving production
      # package fixups enabled and preserving the fixture bytes for host tests.
      postFixup = (old.postFixup or "") + ''
        mkdir -p "$out/libexec/prism-watch-proof"
        cp ResourceFolderModel watch-prerequisite prism-watch.xml \
          "$out/libexec/prism-watch-proof/"
        cp -r ../tests/testdata "$out/libexec/prism-watch-proof/"
      '';
    });
  repaired = proof improved "skip";
  capabilityPresent = pkgs.writeShellApplication {
    name = "prism-watch-capability-present";
    runtimeInputs = [
      pkgs.python3
      pkgs.coreutils
    ];
    text = ''
      export QT_QPA_PLATFORM=offscreen
      export QT_PLUGIN_PATH=${pkgs.kdePackages.qtbase}/${pkgs.kdePackages.qtbase.qtPluginPrefix}
      result=$(mktemp)
      trap 'rm -f "$result"' EXIT
      ${repaired}/libexec/prism-watch-proof/watch-prerequisite
      ${repaired}/libexec/prism-watch-proof/ResourceFolderModel -o "$result",xml
      python3 ${checker} present "$result"
    '';
  };
in
assert upstream.doCheck && improved.doCheck && current.doCheck;
assert upstream.version == improved.version && upstream.version == current.version;
assert current.drvPath != improved.drvPath;
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    prismVersion = upstream.version;
    upstreamPackage = upstream.drvPath;
    currentPackage = current.drvPath;
    improvedPackage = improved.drvPath;
    checksPreserved = upstream.doCheck && current.doCheck && improved.doCheck;
  };
  # Measure capability first, then require the corresponding actual native cases.
  upstreamBehavior = proof upstream "unavailable";
  currentBehavior = proof current "skip";
  improvedBehavior = repaired;
  inherit capabilityPresent checkerRegression;
}
