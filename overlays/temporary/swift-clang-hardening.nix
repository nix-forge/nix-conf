{ pkgs, ... }:
let
  ccSuffix = pkgs.lib.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;
in
{
  reason = "The unwrapped Swift driver does not forward cc-wrapper hardening flags to its Clang importer.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/e7439b6b14ad3cc35d05608ebca9bce01a25f5f8/pkgs/development/compilers/swift/by-name/sw/swift/package.nix";
  removal = "The pinned Swift compiler forwards cc-wrapper hardening flags to Clang and passes the native probe.";
  reviewedRevision = "e7439b6b14ad3cc35d05608ebca9bce01a25f5f8";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      buildCommand = old.buildCommand + ''
        # The upstream package makes swiftc a symlink to swift-driver. Keep the
        # driver in place, and add flags only to compiler invocations.
        test "$(readlink "$out/bin/swiftc")" = swift-driver
        chmod u+w "$out/bin"
        rm "$out/bin/swiftc"
          sed 's/^  //' > "$out/bin/swiftc" <<'WRAPPER'
          #!${pkgs.bash}/bin/bash
          if [[ -n "''${NIX_HARDENING_ENABLE-}" ]]; then
            export NIX_HARDENING_ENABLE_${ccSuffix}="$NIX_HARDENING_ENABLE"
          fi
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
          exec -a "$0" "$(dirname "$0")/swift-driver" "''${flags[@]}" "$@"
        WRAPPER
        chmod +x "$out/bin/swiftc"
        chmod u-w "$out/bin"
      '';
    });
}
