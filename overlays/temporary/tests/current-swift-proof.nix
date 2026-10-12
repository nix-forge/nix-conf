# Compare the current compiler directly, without changing installed review guards.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  repairedSwift = (import ../swift-clang-hardening.nix { inherit pkgs; }).apply pkgs.swift;
in
assert repairedSwift.version == pkgs.swift.version;
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    swiftVersion = pkgs.swift.version;
    upstreamCompiler = pkgs.swift.drvPath;
    repairedCompiler = repairedSwift.drvPath;
  };
  upstream = import ../../../tests/nix/swift-hardening.nix {
    inherit pkgs;
    expectMissingHardening = true;
  };
  repaired = import ../../../tests/nix/swift-hardening.nix {
    pkgs = pkgs // {
      swift = repairedSwift;
    };
  };
}
