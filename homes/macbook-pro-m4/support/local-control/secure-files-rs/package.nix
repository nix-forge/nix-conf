{ pkgs }:
let
  src = pkgs.lib.cleanSource ./.;
in
pkgs.rustPlatform.buildRustPackage {
  pname = "local-control-secure-files";
  version = "0.1.0";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    pkgs.clippy
    pkgs.rustfmt
  ];
  buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    cargo fmt --all -- --check
    cargo clippy --all-targets -- -D warnings
    cargo test --all-targets

    runHook postCheck
  '';

  meta = {
    description = "Descriptor-bound filesystem safety primitives for local-control";
    license = with pkgs.lib.licenses; [
      mit
      asl20
    ];
    platforms = pkgs.lib.platforms.darwin;
  };
}
