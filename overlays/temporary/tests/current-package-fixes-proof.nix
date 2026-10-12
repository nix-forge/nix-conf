# Isolated native package evidence. Installed review guards stay in force.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  apply = name: package: (import (../. + "/${name}.nix") { inherit pkgs lib; }).apply package;
  gtk = apply "gtksourceview-xvfb" pkgs.gtksourceview4;
  hypridle = apply "hypridle-condition-inhibitors" pkgs.hypridle;
  hypridleBaseline = pkgs.hypridle.overrideAttrs (old: {
    nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pkgs.python3 ];
    doCheck = true;
    postCheck = (old.postCheck or "") + ''
      python3 ${./hypridle-condition-inhibitors.py} ../src/core/Hypridle.cpp \
        --expect-unsafe-inhibitor
    '';
  });
  hyprshell = apply "hyprshell-modifiers" pkgs.hyprshell;
  nom = apply "nom-quadratic-build-plan" pkgs.nix-output-monitor;
  plugin = pkgs.pkgsCross.wasi32.navidromePlugins.audiomuseai;
  release = import ../audiomuseai-plugin-release.nix { inherit pkgs lib; };
  repairedPlugin = apply "audiomuseai-plugin-loopback-host" plugin;
  audioMuse =
    pkgs.runCommand "current-audiomuse-loopback-proof"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.unzip
          pkgs.diffutils
        ];
      }
      ''
        # Assert the complete source tree, allowing only the requiredHosts repair.
        cp -R ${plugin.src} upstream
        cp -R ${repairedPlugin.src} repaired
        chmod -R u+w upstream repaired
        jq -e '.permissions.http.requiredHosts == ["*"]' upstream/manifest.json
        jq -e '.permissions.http.requiredHosts == ["127.0.0.1"]' repaired/manifest.json
        jq -S 'del(.permissions.http.requiredHosts)' upstream/manifest.json > upstream-permissions.json
        jq -S 'del(.permissions.http.requiredHosts)' repaired/manifest.json > repaired-permissions.json
        cmp upstream-permissions.json repaired-permissions.json
        rm upstream/manifest.json repaired/manifest.json
        diff -r upstream repaired
        unzip -p ${repairedPlugin}/share/audiomuseai.ndp manifest.json > packed-manifest.json
        jq -e '.permissions.http.requiredHosts == ["127.0.0.1"]' packed-manifest.json
        jq -S . ${repairedPlugin.src}/manifest.json > source-manifest.json
        jq -S . packed-manifest.json > normalized-packed-manifest.json
        cmp source-manifest.json normalized-packed-manifest.json
        mkdir -p "$out"
        cp packed-manifest.json "$out/manifest.json"
      '';
in
assert gtk.doCheck && hypridle.doCheck && hypridleBaseline.doCheck && hyprshell.doCheck;
assert nom.doCheck;
assert
  nom.testTargets == [
    "unit-tests"
    "doc-tests"
  ];
assert
  hyprshell.cargoTestFlags == [
    "--package"
    "hyprshell-windows-lib"
    "event_time_tests"
  ];
assert !(release.appliesTo plugin);
assert plugin.version == "10";
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    packages =
      lib.mapAttrs
        (_: package: {
          inherit (package) version drvPath;
          checksEnabled = package.doCheck or false;
        })
        {
          inherit
            gtk
            hypridle
            hypridleBaseline
            hyprshell
            nom
            ;
          audiomuse = repairedPlugin;
        };
    audioMuseReleaseFixApplicable = release.appliesTo plugin;
    inherit (nom) testTargets;
    inherit (hyprshell) cargoTestFlags;
  };
  inherit
    gtk
    hypridle
    hypridleBaseline
    hyprshell
    nom
    audioMuse
    ;
}
