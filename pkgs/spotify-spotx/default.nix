{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  bash,
  coreutils,
  file,
  findutils,
  gnugrep,
  gnused,
  gnutar,
  perl,
  util-linux,
  unzip,
  zip,
  darwin,
}:

let
  pname = "spotify-spotx";
  source = import ./source.nix;

  spotxSrc = fetchFromGitHub source.spotx;
  spotifySrc = fetchurl { inherit (source.spotify) url hash; };
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  dontUnpack = true;
  dontFixup = true;
  strictDeps = true;

  nativeBuildInputs = [
    bash
    coreutils
    file
    findutils
    gnugrep
    gnused
    gnutar
    perl
    util-linux
    unzip
    zip
    darwin.cctools
    darwin.DarwinTools
    darwin.sigtool
    darwin.system_cmds
  ];

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications/Spotify.app"
    tar -xpf ${spotifySrc} -C "$out/Applications/Spotify.app"
    chmod -R u+rwX "$out/Applications/Spotify.app"

    fakeBin="$TMPDIR/fake-bin"
    install -d "$fakeBin"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fakeBin/curl"
    chmod +x "$fakeBin/curl"

    export HOME="$TMPDIR/home"
    install -d "$HOME"
    export PATH="$fakeBin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"

    bash ${spotxSrc}/spotx.sh \
      --force \
      --blockupdates \
      --premium \
      --noexp \
      --skipcodesign \
      -P "$out/Applications"

    rm -f "$out/Applications/Spotify.app/Contents/MacOS/Spotify.bak"
    rm -f "$out/Applications/Spotify.app/Contents/Resources/Apps/xpui.bak"

    runHook postInstall

    export CODESIGN_ALLOCATE="${darwin.cctools}/bin/codesign_allocate"

    while IFS= read -r executable; do
      if file "$executable" | grep -q 'Mach-O'; then
        codesign --force --entitlements ${./entitlements.plist} --sign - "$executable"
      fi
    done < <(find "$out/Applications/Spotify.app" -type f -perm -0100)

    runHook postInstallCheck
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Spotify for macOS patched with SpotX and ready for Spicetify post-install theming";
    homepage = "https://github.com/SpotX-Official/SpotX-Bash";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
