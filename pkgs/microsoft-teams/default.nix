{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  pbzx,
  cpio,
}:

let
  pname = "microsoft-teams";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [
    xar
    pbzx
    cpio
  ];

  strictDeps = true;

  unpackPhase = ''
    runHook preUnpack

    xar -xf "$src"

    runHook postUnpack
  '';

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications" "$out/bin"
    pbzx -n MicrosoftTeams_app.pkg/Payload | cpio -idm -D "$out/Applications"
    ln -s "$out/Applications/Microsoft Teams.app/Contents/MacOS/MSTeams" "$out/bin/teams"

    runHook postInstall
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Microsoft Teams";
    homepage = "https://teams.microsoft.com";
    downloadPage = "https://teams.microsoft.com/downloads";
    license = lib.licenses.unfree;
    mainProgram = "teams";
    platforms = [
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
