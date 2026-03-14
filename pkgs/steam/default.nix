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
    cp ${./Steam.icns} "$workdir/Steam.app/Contents/Resources/Steam.icns"
    mv "$workdir/Steam.app/Contents/MacOS/steam_osx" "$workdir/Steam.app/Contents/MacOS/steam_osx.real"

    cat > "$workdir/Steam.app/Contents/MacOS/steam_osx" <<'EOF'
    #!/bin/sh
    set -eu

    app_macos_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    packaged_icon="$(CDPATH= cd -- "$app_macos_dir/../Resources" && pwd)/Steam.icns"
    installed_client="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx"
    installed_plist="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/Info.plist"
    installed_resources="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/Resources"
    bootstrapper="$app_macos_dir/steam_osx.real"
    restart_attempts=0
    restart_limit=5

    sync_icon_metadata() {
      plist_path="$1"
      resources_path="$2"
      icon_path="$resources_path/Steam.icns"

      if [ -f "$packaged_icon" ] && { [ ! -f "$icon_path" ] || ! cmp -s "$packaged_icon" "$icon_path"; }; then
        cp "$packaged_icon" "$icon_path"
      fi

      if [ -f "$plist_path" ]; then
        if /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist_path" >/dev/null 2>&1; then
          /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile Steam.icns' "$plist_path" >/dev/null 2>&1 || true
        else
          /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Steam.icns' "$plist_path" >/dev/null 2>&1 || true
        fi
      fi
    }

    while :; do
      if [ -x "$installed_client" ]; then
        sync_icon_metadata "$installed_plist" "$installed_resources"
        target="$installed_client"
      else
        target="$bootstrapper"
        if [ "$restart_attempts" -eq 0 ]; then
          echo "Steam is bootstrapping the full client into ~/Library/Application Support/Steam." >&2
          echo "This first launch may take a minute before the UI appears." >&2
        fi
      fi

      status=0
      "$target" "$@" || status=$?

      if [ "$status" -eq 42 ]; then
        restart_attempts=$((restart_attempts + 1))
        if [ "$restart_attempts" -gt "$restart_limit" ]; then
          echo "Steam requested too many automatic restarts." >&2
          exit 42
        fi
        sleep 1
        continue
      fi

      if [ "$target" = "$bootstrapper" ] && [ -x "$installed_client" ]; then
        sync_icon_metadata "$installed_plist" "$installed_resources"
        echo "Steam bootstrap completed; launching the installed client directly." >&2
        restart_attempts=$((restart_attempts + 1))
        sleep 1
        continue
      fi

      if [ "$target" = "$bootstrapper" ] && [ ! -x "$installed_client" ]; then
        echo "Steam bootstrap did not produce an installed client at:" >&2
        echo "  $installed_client" >&2
        exit 1
      fi

      exit "$status"
    done
    EOF
    chmod 0555 "$workdir/Steam.app/Contents/MacOS/steam_osx"
    cp -a "$workdir/Steam.app" "$out/Applications/"

    cat > "$out/bin/${pname}" <<EOF
    #!/bin/sh
    exec "${placeholder "out"}/Applications/Steam.app/Contents/MacOS/steam_osx" "\$@"
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
