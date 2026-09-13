{ pkgs, ... }: {
  reason = "The Swift wrapper reads the removed hardeningCFlags array and drops Clang importer hardening flags.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0/pkgs/development/compilers/swift/wrapper/wrapper.sh";
  removal = "The pinned Swift wrapper forwards both cc-wrapper hardening arrays in the intended order and passes the native hardening probe.";
  reviewedRevision = "c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    let
      repaired = package.overrideAttrs (old: {
        # This derivation uses buildCommand; phase hooks such as postFixup do
        # not run. Fail on changed source instead of silently accepting drift.
        buildCommand = old.buildCommand + ''
          for executable in swift swiftc swift-frontend; do
            substituteInPlace "$out/bin/$executable" \
              --replace-fail \
                'addCFlagsToList extraBefore ''${hardeningCFlags[@]+"''${hardeningCFlags[@]}"}' \
                'addCFlagsToList extraBefore ''${hardeningCFlagsBefore[@]+"''${hardeningCFlagsBefore[@]}"}' \
              --replace-fail \
                'addCFlagsToList extraAfter $NIX_CFLAGS_COMPILE_' \
                'addCFlagsToList extraAfter ''${hardeningCFlagsAfter[@]+"''${hardeningCFlagsAfter[@]}"} $NIX_CFLAGS_COMPILE_'
          done
        '';
      });
    in
    repaired.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        tests = (old.passthru.tests or { }) // {
          hardening =
            pkgs.runCommandCC "swift-wrapper-hardening"
              {
                nativeBuildInputs = [ repaired ];
                hardeningEnable = [
                  "fortify"
                  "stackprotector"
                ];
              }
              ''
                cat > module.modulemap <<'MODULE'
                module HardeningProbe {
                  header "probe.h"
                  export *
                }
                MODULE
                cat > probe.h <<'HEADER'
                #if !defined(_FORTIFY_SOURCE) || _FORTIFY_SOURCE != 2
                #error Clang importer is missing the fortify setting
                #endif
                #if !defined(__SSP_STRONG__) || __SSP_STRONG__ != 2
                #error Clang importer is missing strong stack protection
                #endif
                static inline int hardening_probe(void) { return 42; }
                HEADER
                cat > probe.swift <<'SWIFT'
                import Darwin
                import HardeningProbe
                print("Swift hardening probe \(hardening_probe())")
                SWIFT
                # A compile-and-link log also contains cc-wrapper flags from
                # linking. Typecheck separately to isolate the Clang importer.
                if ! NIX_DEBUG=1 swiftc -O -I . -typecheck probe.swift 2> compiler.log; then
                  cat compiler.log >&2
                  exit 1
                fi
                grep -F -- '-fstack-protector-strong' compiler.log
                grep -F -- '-D_FORTIFY_SOURCE=2' compiler.log
                swiftc -O -I . probe.swift -o probe
                ./probe | grep -Fx 'Swift hardening probe 42'
                mkdir "$out"
                cp compiler.log "$out/"
              '';
        };
      };
    });
}
