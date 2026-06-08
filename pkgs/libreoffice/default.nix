{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  pname = "libreoffice";
  source = import ./source.nix;
  appName = "LibreOffice.app";
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.sources.${stdenvNoCC.hostPlatform.system};
  nativeBuildInputs = [ undmg ];
  sourceRoot = appName;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications/${appName}" "$out/bin"
    cp -R . "$out/Applications/${appName}"
    ln -s "$out/Applications/${appName}/Contents/MacOS/soffice" "$out/bin/soffice"
    ln -s "$out/bin/soffice" "$out/bin/libreoffice"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Comprehensive, professional-quality productivity suite";
    homepage = "https://www.libreoffice.org/";
    downloadPage = "https://www.libreoffice.org/download/download-libreoffice/";
    license = lib.licenses.lgpl3;
    mainProgram = "libreoffice";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
