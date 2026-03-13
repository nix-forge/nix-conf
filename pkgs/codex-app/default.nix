{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "codex-app";
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
    cp -a Codex.app "$out/Applications/"
    ln -s "$out/Applications/Codex.app/Contents/MacOS/Codex" "$out/bin/${pname}"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "OpenAI's Codex desktop app for managing coding agents";
    homepage = "https://openai.com/codex";
    license = lib.licenses.unfree;
    mainProgram = pname;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
