{ pkgs, ... }: {
  reason = "The unwrapped Swift driver does not forward cc-wrapper hardening flags to its Clang importer.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/development/compilers/swift/by-name/sw/swift/package.nix";
  removal = "The pinned Swift compiler forwards cc-wrapper hardening flags to Clang and passes the native probe.";
  reviewedRevision = "c59305bab2065cfecc4944690d9eedbb56f3a9fa";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      buildCommand = old.buildCommand + ''
        # The upstream package makes swiftc a symlink to swift-driver. Keep the
        # driver in place, and add flags only to compiler invocations.
        test "$(readlink "$out/bin/swiftc")" = swift-driver
        rm "$out/bin/swiftc"
        cat > "$out/bin/swiftc" <<'WRAPPER'
        #!${pkgs.bash}/bin/bash
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
        exec -a "$0" "$(dirname "$0")/swift-driver" "''${flags[@]}" "$@"
        WRAPPER
        chmod +x "$out/bin/swiftc"
      '';
    });
}
