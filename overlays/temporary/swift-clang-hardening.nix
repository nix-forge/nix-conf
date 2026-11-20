{ myLib, pkgs, ... }:
let
  inherit (pkgs) lib;
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  ccSuffix = lib.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;
  swiftc = pkgs.writeTextFile {
    name = "swiftc-hardening-wrapper";
    executable = true;
    text = checkedShellText {
      name = "swiftc-hardening-wrapper";
      # The compiler supplies hardeningCFlagsBefore and hardeningCFlagsAfter.
      shellcheckFlags = [ "--exclude=SC2154" ];
      text = ''
        #!${pkgs.bash}/bin/bash
        if [[ -n "''${NIX_HARDENING_ENABLE-}" ]]; then
          export NIX_HARDENING_ENABLE_${ccSuffix}="$NIX_HARDENING_ENABLE"
        fi
        # The compiler wrapper provides these arrays at runtime.
        # shellcheck source=/dev/null
        source ${pkgs.stdenv.cc}/nix-support/add-hardening.sh
        flags=()
        for flag in "''${hardeningCFlagsBefore[@]}"; do
          flags+=(-Xcc "$flag")
        done
        for flag in ''${NIX_CFLAGS_COMPILE_BEFORE-}; do
          flags+=(-Xcc "$flag")
        done
        for flag in "''${hardeningCFlagsAfter[@]}"; do
          flags+=(-Xcc "$flag")
        done
        for flag in ''${NIX_CFLAGS_COMPILE-}; do
          flags+=(-Xcc "$flag")
        done
        if (( ''${NIX_DEBUG:-0} >= 1 )); then
          printf 'Swift Clang flags:' >&2
          printf ' %q' "''${hardeningCFlagsBefore[@]}" "''${hardeningCFlagsAfter[@]}" >&2
          printf '\n' >&2
        fi
        # SwiftPM's link environment can omit command-line tools from PATH.
        driver_directory=''${0%/*}
        if [[ "$driver_directory" == "$0" ]]; then
          driver_directory=.
        fi
        exec -a "$0" "''${driver_directory:-/}/swift-driver" "''${flags[@]}" "$@"
      '';
    };
  };
in
{
  reason = "The unwrapped Swift driver does not forward cc-wrapper hardening flags to its Clang importer.";
  upstream = "https://github.com/NixOS/nixpkgs/pull/566624";
  removal = "The pinned Swift compiler forwards cc-wrapper hardening flags to Clang and passes the native probe.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      buildCommand =
        old.buildCommand
        + checkedShellText {
          name = "install-swift-hardening-wrapper";
          text = ''
            # Keep swift-driver in place and install the checked wrapper alongside it.
            # stdenv sets out in the build environment.
            # shellcheck disable=SC2154
            test "$(readlink "$out/bin/swiftc")" = swift-driver
            chmod u+w "$out/bin"
            rm "$out/bin/swiftc"
            install -m 0755 ${swiftc} "$out/bin/swiftc"
            chmod u-w "$out/bin"
          '';
        };
    });
}
