{ pkgs, rust }:
let
  inherit (pkgs) lib;
  version = "0.68.0";
  # Kani links to the compiler internals from this nightly.
  nightly = "2026-08-21";
  toolchain = rust.nightly.${nightly}.minimal;
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
  target = pkgs.stdenv.hostPlatform.rust.rustcTarget;
  hash =
    {
      x86_64-unknown-linux-gnu = "sha256-MuK0hNc+3gu/ZKLPCHnEJZQiSX2K7E7mfUSN6a54Q9M=";
      aarch64-unknown-linux-gnu = "sha256-AELSaIvxVQJw3vSnnJaq7qE4YxgYy0q1SAEg8tUalCw=";
      aarch64-apple-darwin = "sha256-pdOaXV50glOlU6pi8pXGw5coeSeijl4yaR1/8u2gw5g=";
      x86_64-apple-darwin = "sha256-sTZ/aUwTUKvK4TNwH3izvj/W6b62ZoGiLqC8rAzDSAg=";
    }
    .${target};
in
pkgs.stdenv.mkDerivation {
  pname = "kani";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://github.com/model-checking/kani/releases/download/kani-${version}/kani-${version}-${target}.tar.gz";
    inherit hash;
  };
  nativeBuildInputs = [ pkgs.makeWrapper ] ++ lib.optionals isLinux [ pkgs.autoPatchelfHook ];
  buildInputs = [ toolchain ] ++ lib.optionals isLinux [ (lib.getLib pkgs.stdenv.cc.cc) ];
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    grep -Fx 'nightly-${nightly}-${target}' rust-toolchain-version
    mkdir -p "$out/bin" "$out/libexec/kani"
    cp -r . "$out/libexec/kani"
    ln -s ${toolchain} "$out/libexec/kani/toolchain"
    ${lib.optionalString isDarwin ''
      # goto-cc looks for gcc even when the platform compiler is Clang.
      ln -s ${pkgs.stdenv.cc}/bin/cc "$out/libexec/kani/bin/gcc"
    ''}
    makeWrapper "$out/libexec/kani/bin/kani-driver" "$out/bin/cargo-kani" \
      --argv0 cargo-kani \
      --prefix PATH : "$out/libexec/kani/bin" \
      --unset RUSTC_WRAPPER --unset RUSTC_WORKSPACE_WRAPPER
    runHook postInstall
  '';
  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/cargo-kani";
  doInstallCheck = true;
  meta = {
    description = "Kani model checker and its matching Rust toolchain";
    homepage = "https://model-checking.github.io/kani/";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "cargo-kani";
  };
}
