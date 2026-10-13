# Test the selected wrapper with inert binaries, without launching a vendor browser.
# A hosted filesystem pass does not establish retirement on the native builder mount.
let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  repair = (import ../zen-wrapper-copy.nix { inherit lib; }).apply pkgs.wrapFirefox;
  fixture =
    name:
    pkgs.runCommand name
      {
        pname = name;
        version = "1.0";
        applicationName = "Wrapper Fixture";
        binaryName = name;
        passthru = {
          inherit (pkgs) gtk3;
          enableAddonSigning = true;
          enableAddonSideload = false;
        };
        meta.license = lib.licenses.mit;
      }
      ''
        mkdir -p "$out/bin" "$out/lib/${name}"
        cat > "$out/bin/${name}" <<'BINARY'
        #!${pkgs.runtimeShell}
        printf '%s\n' 'wrapper fixture runtime'
        BINARY
        chmod +x "$out/bin/${name}"
        printf '%s\n' 'preserved wrapper fixture data' > "$out/lib/${name}/fixture.txt"
        ln -s fixture.txt "$out/lib/${name}/fixture.link"
      '';
  zen = fixture "zen-wrapper-fixture";
  firefox = fixture "firefox-wrapper-fixture";
  arguments = {
    withGlvnd = false;
  };
  upstreamZen = pkgs.wrapFirefox zen arguments;
  repairedZen = repair zen arguments;
  upstreamFirefox = pkgs.wrapFirefox firefox arguments;
  repairedFirefox = repair firefox arguments;
  check =
    browser: wrapped:
    pkgs.runCommand "${browser.pname}-invariants" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
      binary=${lib.escapeShellArg browser.binaryName}
      test -x "${wrapped}/bin/$binary"
      "${wrapped}/bin/$binary" | grep -Fx 'wrapper fixture runtime'
      cmp "${browser}/bin/$binary" "${wrapped}/bin/.$binary-old"
      test "$(stat -c '%a' "${browser}/bin/$binary")" \
        = "$(stat -c '%a' "${wrapped}/bin/.$binary-old")"
      cmp "${browser}/lib/$binary/fixture.txt" "${wrapped}/lib/$binary/fixture.txt"
      test "$(readlink "${wrapped}/lib/$binary/fixture.link")" = fixture.txt
      touch "$out"
    '';
in
assert lib.hasInfix "cp -P --no-preserve=mode,ownership --remove-destination"
  upstreamZen.buildCommand;
assert !(lib.hasInfix "--no-preserve=mode,ownership" repairedZen.buildCommand);
assert upstreamFirefox.drvPath == repairedFirefox.drvPath;
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    coreutilsVersion = pkgs.coreutils.version;
    ordinaryFirefoxUnchanged = upstreamFirefox.drvPath == repairedFirefox.drvPath;
  };
  zen = check zen repairedZen;
  firefox = check firefox repairedFirefox;
}
