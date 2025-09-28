{
  lib,
  stdenvNoCC,
  writeShellApplication,
  curl,
  git,
  gnused,
  gawk,
  jq,
  nix,
}:
let
  version = "140.0";
  userJsSrc = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/arkenfox/user.js/${version}/user.js";
    sha256 = "sha256-/cz0dnQXKa3c/DqUTAEwBV0I9Tc3x6uzU6rtYijg3Zo=";
  };
  updateScriptDrv = writeShellApplication {
    name = "update-arkenfox-user-js";
    runtimeInputs = [
      curl
      git
      gnused
      gawk
      jq
      nix
    ];
    text = builtins.readFile ./update.sh;
  };
in
stdenvNoCC.mkDerivation {
  pname = "arkenfox-user-js";
  inherit version;
  src = userJsSrc;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm644 $src $out/user.js
    install -Dm644 $src $out/user.cfg
    substituteInPlace $out/user.cfg \
      --replace-fail "user_pref" "defaultPref"

    runHook postInstall
  '';

  passthru = {
    inherit userJsSrc;
    updateScript = {
      command = [ "${updateScriptDrv}/bin/update-arkenfox-user-js" ];
    };
    updateScriptPackage = updateScriptDrv;
  };

  meta = {
    description = "A comprehensive user.js template for configuration and hardening";
    homepage = "https://github.com/arkenfox/user.js";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
