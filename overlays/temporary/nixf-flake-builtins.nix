{
  lib,
  myLib,
  pkgs,
  ...
}:
let
  inherit (pkgs) nixf;
  nixExpr = lib.findSingle (input: lib.getName input == "nix-expr") null null nixf.buildInputs;
  nixFlake = pkgs.nixVersions.latest.libs.nix-flake;
  patch = builtins.path {
    path = ./patches/nixf-flake-builtins.patch;
    name = "nixf-flake-builtins.patch";
  };
  repairedNixf =
    if
      !(
        nixf.version == "2.9.4"
        &&
          (nixf.src.hash or nixf.src.outputHash or null)
          == "sha256-iBoajmSfgWQ7dJGrL8I2qgK+TsS1lDTnGSTo/qwsfbc="
      )
    then
      throw "Temporary upstream fix 'nixf-flake-builtins' needs review: frontend source changed."
    else if
      !(nixExpr != null && nixExpr.version == "2.35.6" && nixFlake.version == nixExpr.version)
    then
      throw "Temporary upstream fix 'nixf-flake-builtins' needs review: owning Nix libraries changed."
    else
      nixf.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ patch ];
        patchFlags = [
          "-p1"
          "--fuzz=0"
        ];
        buildInputs = old.buildInputs ++ [ nixFlake ];
        postPatch =
          (old.postPatch or "")
          + (myLib.templates.renderText
            {
              name = "prepare-nixf-flake-header.sh";
              text = ''
                # shellcheck shell=bash
                # The SDK omits this private declaration while exporting its real primop symbols.
                printf '%s  %s\n' '@sourceHeaderSHA256@' @sourceHeader@ |
                  @sha256sum@ --check --status || exit $?
                @install@ -Dm644 @sourceHeader@ src/nix/flake/flake-primops.hh
              '';
            }
            {
              sourceHeader = lib.escapeShellArg "${nixFlake.src}/src/libflake/include/nix/flake/flake-primops.hh";
              sourceHeaderSHA256 = "c97ba016d8e08f7168a750133c7e91726b1f85febd4a5fbe6fd504b122bfda1b";
              sha256sum = lib.getExe' pkgs.coreutils "sha256sum";
              install = lib.getExe' pkgs.coreutils "install";
            }
          );
      });
in
{
  reason = "nixf's expression-only builtin table omits the supported flake primops and rejects valid getFlake calls.";
  upstream = "https://github.com/nix-community/nixd/issues/762";
  removal = "The unmodified nixf frontend registers the selected Nix flake primop metadata and passes the valid-flake and unknown-builtin install checks.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "0.1.4";
    until = "0.1.5";
  };
  apply =
    package:
    if
      (package.src.hash or package.src.outputHash or null)
      != "sha256-vHW2AnUxBuG9mlpMB0f9eK4M1VlJPm5YtwjXksx/uik="
    then
      throw "Temporary upstream fix 'nixf-flake-builtins' needs review: diagnostic wrapper source changed."
    else
      (package.override { nixf = repairedNixf; }).overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          nixfFlakeFrontend = repairedNixf;
        };
      });
}
