{ lib, pkgs }:
{
  reason = "VS Code loads the TextMate tokenizer from node_modules.asar.unpacked after Nixpkgs removes that directory.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0/pkgs/applications/editors/vscode/generic.nix#L409-L432";
  removal = "The Nixpkgs VS Code package preserves a browser-readable vscode-oniguruma WASM path.";
  reviewedRevision = "c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (
      final: old: {
        postInstall = (old.postInstall or "") + ''
          oniguruma="$out/lib/vscode/resources/app/node_modules/vscode-oniguruma"
          browser_modules="$out/lib/vscode/resources/app/node_modules.asar.unpacked"

          test -r "$oniguruma/release/onig.wasm"
          mkdir -p "$browser_modules"
          ln -s ../node_modules/vscode-oniguruma "$browser_modules/vscode-oniguruma"
        '';

        passthru = (old.passthru or { }) // {
          tests = (old.passthru.tests or { }) // {
            oniguruma-layout = pkgs.runCommand "vscode-oniguruma-layout" { } ''
              ${lib.getExe pkgs.bash} ${../../tests/vscode/check_oniguruma_layout.sh} \
                ${final.finalPackage}/lib/vscode/resources/app
              touch "$out"
            '';
          };
        };
      }
    );
}
