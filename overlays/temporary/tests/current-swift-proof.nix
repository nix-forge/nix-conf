# Compare the current compiler directly, without changing installed review guards.
let
  root = toString ../../..;
  flake = builtins.getFlake ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  upstreamSwift = pkgs.swiftPackages.swift;
  repairedSwift = (import ../swift-clang-hardening.nix { inherit pkgs; }).apply upstreamSwift;
in
assert repairedSwift.version == upstreamSwift.version;
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    swiftVersion = upstreamSwift.version;
    upstreamCompiler = upstreamSwift.drvPath;
    repairedCompiler = repairedSwift.drvPath;
  };
  upstream = import ../../../tests/nix/swift-hardening.nix {
    pkgs = pkgs // {
      swift = upstreamSwift;
    };
    expectMissingHardening = true;
  };
  repaired = import ../../../tests/nix/swift-hardening.nix {
    pkgs = pkgs // {
      swift = repairedSwift;
    };
  };
}
