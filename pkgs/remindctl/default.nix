{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "remindctl";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 remindctl "$out/bin/${pname}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test "$("$out/bin/${pname}" --version)" = "${finalAttrs.version}"

    runHook postInstallCheck
  '';

  passthru = {
    agentSkill = ./SKILL.md;
    updateScript = [ ./update.py ];
  };

  meta = {
    description = "Fast command-line access to Apple Reminders";
    homepage = "https://remindctl.sh";
    downloadPage = "https://github.com/openclaw/remindctl/releases";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
