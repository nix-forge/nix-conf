{
  pkgs,
  expectMissingHardening ? false,
}:
pkgs.runCommandCC
  "swift-hardening${pkgs.lib.optionalString expectMissingHardening "-upstream-review"}"
  {
    nativeBuildInputs = [ pkgs.swift ];
    hardeningEnable = [
      "fortify"
      "stackprotector"
    ];
  }
  ''
    swiftc --version
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
    # A compile-and-link log also contains cc-wrapper flags from linking.
    # Typecheck separately to isolate the Clang importer.
    ${
      if expectMissingHardening then
        ''
          if NIX_DEBUG=1 swiftc -O -I . -typecheck probe.swift 2> compiler.log; then
            echo 'FAIL: upstream compiler unexpectedly supplies importer hardening' >&2
            exit 1
          fi
          cat compiler.log
          grep -F 'error: Clang importer is missing the fortify setting' compiler.log
          grep -F 'error: Clang importer is missing strong stack protection' compiler.log
          # An SDK, linker, or unrelated compiler failure is not a baseline verdict.
          if grep 'error:' compiler.log | grep -vE \
            "error: (Clang importer is missing the fortify setting|Clang importer is missing strong stack protection|could not build (C|Objective-C) module 'HardeningProbe')"; then
            echo 'FAIL: unrelated compiler diagnostic in upstream baseline' >&2
            exit 1
          fi
          mkdir "$out"
          cp compiler.log "$out/"
        ''
      else
        ''
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
        ''
    }
  ''
