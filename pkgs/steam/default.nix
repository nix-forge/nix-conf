{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "steam";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.appdmg;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    workdir="$PWD/work"
    install -d "$workdir" "$out/Applications" "$out/bin"

    unzip -qq "$src" 'SteamMacBootstrapper.tar.gz' -d "$workdir"
    tar -xzf "$workdir/SteamMacBootstrapper.tar.gz" -C "$workdir"

    find "$workdir/Steam.app" -name '._*' -delete
    cp -a "$workdir/Steam.app" "$out/Applications/"

    cat > "$out/bin/${pname}" <<EOF
    #!/bin/sh
    set -eu

    installed_client="\$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx"
    bootstrapper="${placeholder "out"}/Applications/Steam.app/Contents/MacOS/steam_osx"
    restart_attempts=0
    restart_limit=5

    while :; do
      if [ -x "\$installed_client" ]; then
        target="\$installed_client"
      else
        target="\$bootstrapper"
        if [ "\$restart_attempts" -eq 0 ]; then
          echo "Steam is bootstrapping into ~/Library/Application Support/Steam." >&2
        fi
      fi

      status=0
      "\$target" "\$@" || status=\$?

      if [ "\$status" -eq 42 ]; then
        restart_attempts=\$((restart_attempts + 1))
        if [ "\$restart_attempts" -gt "\$restart_limit" ]; then
          echo "Steam requested too many automatic restarts." >&2
          exit 42
        fi
        sleep 1
        continue
      fi

      if [ "\$target" = "\$bootstrapper" ] && [ -x "\$installed_client" ]; then
        restart_attempts=\$((restart_attempts + 1))
        sleep 1
        continue
      fi

      if [ "\$target" = "\$bootstrapper" ] && [ ! -x "\$installed_client" ]; then
        echo "Steam bootstrap did not produce an installed client at:" >&2
        echo "  \$installed_client" >&2
        exit 1
      fi

      exit "\$status"
    done
    EOF
    chmod 0555 "$out/bin/${pname}"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Valve's official Steam app bundle for macOS";
    homepage = "https://store.steampowered.com/about/";
    license = lib.licenses.unfree;
    mainProgram = pname;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
