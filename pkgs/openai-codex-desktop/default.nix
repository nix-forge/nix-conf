{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "openai-codex-desktop";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) appName version;

  src = fetchurl source.src;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;
  # The signed upstream app bundle includes non-macOS helper binaries. Generic
  # fixup tries to run Linux `patchelf` on those files, which is irrelevant on
  # Darwin and only produces noisy warnings.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications" "$out/bin"
    cp -a "$appName.app" "$out/Applications/"
    ln -s "$out/Applications/$appName.app/Contents/MacOS/$appName" "$out/bin/${pname}"

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
