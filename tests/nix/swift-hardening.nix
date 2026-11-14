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
  (
    (import ../../lib/templates/text.nix) ./scripts/check-swift-hardening.sh {
      moduleMap = ./scripts/hardening-probe.modulemap;
      header = ./scripts/hardening-probe.h;
      swiftSource = ./scripts/hardening-probe.swift;
      expectMissingHardening = if expectMissingHardening then "true" else "false";
    }
  )
