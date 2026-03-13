{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "claude-desktop";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications" "$out/bin"
    cp -a Claude.app "$out/Applications/"
    ln -s "$out/Applications/Claude.app/Contents/MacOS/Claude" "$out/bin/${pname}"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Anthropic's official Claude AI desktop app";
    homepage = "https://claude.com/download";
    license = lib.licenses.unfree;
    mainProgram = pname;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
