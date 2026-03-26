{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
  makeWrapper,
}:

let
  pname = "opencode-cursor";
  source = import ./source.nix;

  opencodePluginSrc = fetchurl source.runtimeDeps.opencodePlugin.src;
  opencodeSdkSrc = fetchurl source.runtimeDeps.opencodeSdk.src;
  zodSrc = fetchurl source.runtimeDeps.zod.src;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ makeWrapper ];
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    install -d "$out/lib/${pname}" "$out/bin" "$out/lib/${pname}/node_modules/@opencode-ai" "$out/lib/${pname}/node_modules"
    cp -a . "$out/lib/${pname}/"

    install -d "$out/lib/${pname}/node_modules/@opencode-ai/plugin"
    tar -xzf ${opencodePluginSrc} --strip-components=1 -C "$out/lib/${pname}/node_modules/@opencode-ai/plugin"

    install -d "$out/lib/${pname}/node_modules/@opencode-ai/sdk"
    tar -xzf ${opencodeSdkSrc} --strip-components=1 -C "$out/lib/${pname}/node_modules/@opencode-ai/sdk"

    install -d "$out/lib/${pname}/node_modules/zod"
    tar -xzf ${zodSrc} --strip-components=1 -C "$out/lib/${pname}/node_modules/zod"

    makeWrapper ${lib.getExe nodejs} "$out/bin/open-cursor" \
      --add-flags "$out/lib/${pname}/dist/cli/opencode-cursor.js"
    makeWrapper ${lib.getExe nodejs} "$out/bin/cursor-discover" \
      --add-flags "$out/lib/${pname}/dist/cli/discover.js"
    makeWrapper ${lib.getExe nodejs} "$out/bin/mcptool" \
      --add-flags "$out/lib/${pname}/dist/cli/mcptool.js"

    runHook postInstall
  '';

  meta = {
    description = "Use Cursor Pro models in OpenCode via HTTP proxy with OAuth";
    homepage = "https://github.com/Nomadcxx/opencode-cursor";
    license = lib.licenses.isc;
    mainProgram = "open-cursor";
    platforms = lib.platforms.unix;
  };
}
