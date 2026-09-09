{ myLib, ... }: {
  lib.localControl =
    let
      writeBashTemplate = pkgs: myLib.writers.writeBashTemplate { inherit pkgs; };
      mkSecureFileSystem =
        pkgs:
        let
          src = pkgs.lib.fileset.toSource {
            root = ./secure-files-rs;
            fileset = pkgs.lib.fileset.unions [
              ./secure-files-rs/Cargo.toml
              ./secure-files-rs/Cargo.lock
              ./secure-files-rs/rust-toolchain.toml
              ./secure-files-rs/src
              ./secure-files-rs/tests
            ];
          };
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
        };

      mkEnvironmentSnapshot =
        pkgs:
        let
          secureFileSystem = mkSecureFileSystem pkgs;
        in
        writeBashTemplate pkgs {
          name = "local-control-environment-snapshot";
          src = ./scripts/environment-snapshot.sh;
          dir = "bin";
          replacements = {
            bash = "${pkgs.bash}/bin/bash";
            mktemp = "${pkgs.coreutils}/bin/mktemp";
            rm = "${pkgs.coreutils}/bin/rm";
            cat = "${pkgs.coreutils}/bin/cat";
            secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
          };
        };

      mkSourceTreeSnapshot =
        pkgs:
        writeBashTemplate pkgs {
          name = "local-control-source-snapshot";
          src = ./scripts/source-tree-snapshot.sh;
          dir = "bin";
          replacements = {
            bash = "${pkgs.bash}/bin/bash";
            secureFileSystem = "${mkSecureFileSystem pkgs}/bin/local-control-secure-files";
          };
        };

      mkPreparationProof =
        pkgs:
        let
          environmentSnapshot = mkEnvironmentSnapshot pkgs;
          secureFileSystem = mkSecureFileSystem pkgs;
          sourceIdentity = writeBashTemplate pkgs {
            name = "local-control-source-identity";
            src = ./scripts/source-identity.sh;
            dir = "bin";
            replacements = {
              bash = "${pkgs.bash}/bin/bash";
              secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
              git = "${pkgs.git}/bin/git";
              sha256sum = "${pkgs.coreutils}/bin/sha256sum";
              cut = "${pkgs.coreutils}/bin/cut";
            };
          };
        in
        writeBashTemplate pkgs {
          name = "local-control-preparation-proof";
          src = ./scripts/preparation-proof.sh;
          dir = "bin";
          replacements = {
            bash = "${pkgs.bash}/bin/bash";
            mktemp = "${pkgs.coreutils}/bin/mktemp";
            rm = "${pkgs.coreutils}/bin/rm";
            environmentSnapshot = "${environmentSnapshot}/bin/local-control-environment-snapshot";
            secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
            sourceIdentity = "${sourceIdentity}/bin/local-control-source-identity";
            sha256sum = "${pkgs.coreutils}/bin/sha256sum";
            cut = "${pkgs.coreutils}/bin/cut";
          };
        };

      mkPrivatePathGuard =
        pkgs:
        let
          secureFileSystem = mkSecureFileSystem pkgs;
        in
        writeBashTemplate pkgs {
          name = "local-control-private-path";
          src = ./scripts/private-path-guard.sh;
          dir = "bin";
          replacements = {
            bash = "${pkgs.bash}/bin/bash";
            secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
          };
        };

      mkPreparationGate =
        pkgs:
        let
          environmentSnapshot = mkEnvironmentSnapshot pkgs;
          preparationProof = mkPreparationProof pkgs;
          secureFileSystem = mkSecureFileSystem pkgs;
        in
        writeBashTemplate pkgs {
          name = "local-control-service-gate";
          src = ./scripts/preparation-gate.sh;
          dir = "bin";
          replacements = {
            bash = "${pkgs.bash}/bin/bash";
            mktemp = "${pkgs.coreutils}/bin/mktemp";
            rm = "${pkgs.coreutils}/bin/rm";
            environmentSnapshot = "${environmentSnapshot}/bin/local-control-environment-snapshot";
            preparationProof = "${preparationProof}/bin/local-control-preparation-proof";
            secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
          };
        };

      mkDatabaseClusterValidator =
        pkgs:
        let
          secureFileSystem = mkSecureFileSystem pkgs;
        in
        writeBashTemplate pkgs {
          name = "local-control-validate-database-cluster";
          src = ./scripts/database-cluster-validator.sh;
          dir = "bin";
          replacements = {
            bash = "${pkgs.bash}/bin/bash";
            secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
            pgControldata = "${pkgs.postgresql_18}/bin/pg_controldata";
          };
        };
    in
    {
      inherit
        mkEnvironmentSnapshot
        mkPreparationGate
        mkPreparationProof
        mkPrivatePathGuard
        mkSecureFileSystem
        mkSourceTreeSnapshot
        mkDatabaseClusterValidator
        ;
    };
}
