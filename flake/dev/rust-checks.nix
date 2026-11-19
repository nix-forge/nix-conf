_: {
  perSystem =
    { pkgs, ... }:
    let
      workspace = import ../rust-workspace.nix { inherit pkgs; };
      clippyExclusions = pkgs.lib.concatMapStrings (
        crate: " --exclude ${pkgs.lib.escapeShellArg crate}"
      ) workspace.unsupportedCrates;
    in
    {
      checks =
        pkgs.lib.mapAttrs' (
          _: package: pkgs.lib.nameValuePair "rust-${package.pname}" package
        ) workspace.supportedPackages
        // {
          rust-quality = pkgs.rustPlatform.buildRustPackage (
            workspace.commonBuildArgs
            // {
              pname = "runtime-rust-quality";
              inherit (workspace) version buildInputs;
              nativeBuildInputs = pkgs.lib.unique (
                workspace.nativeBuildInputs
                ++ [
                  pkgs.clippy
                  pkgs.cargo-deny
                  pkgs.rustfmt
                  pkgs.pkg-config
                ]
              );
              buildPhase = ''
                runHook preBuild
                cargo fmt --all -- --check
                cargo clippy --workspace ${clippyExclusions} --all-targets --locked --offline -- -D warnings
                RUSTDOCFLAGS="-D warnings" cargo doc --workspace ${clippyExclusions} --no-deps --locked --offline
                cargo deny --locked --offline check bans licenses sources
                runHook postBuild
              '';
              doCheck = false;
              installPhase = ''
                touch "$out"
              '';
              # This output is a check marker, not the application binary.
              postInstall = "";
              doInstallCheck = false;
            }
          );
        };
    };
}
