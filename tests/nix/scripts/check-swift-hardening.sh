# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
swiftc --version
cp @moduleMap@ module.modulemap
cp @header@ probe.h
cp @swiftSource@ probe.swift
# A compile-and-link log also contains cc-wrapper flags from linking.
# Typecheck separately to isolate the Clang importer.
if @expectMissingHardening@; then
  if NIX_DEBUG=1 swiftc -O -I . -typecheck probe.swift 2>compiler.log; then
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
else
  if ! NIX_DEBUG=1 swiftc -O -I . -typecheck probe.swift 2>compiler.log; then
    cat compiler.log >&2
    exit 1
  fi
  grep -F -- '-fstack-protector-strong' compiler.log
  grep -F -- '-D_FORTIFY_SOURCE=2' compiler.log
  swiftc -O -I . probe.swift -o probe
  ./probe | grep -Fx 'Swift hardening probe 42'
fi
mkdir "$out"
cp compiler.log "$out/"
