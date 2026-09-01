_:
let
  mkSecureFileSystem = pkgs: import ./secure-files-rs/package.nix { inherit pkgs; };

  mkEnvironmentSnapshot =
    pkgs:
    let
      secureFileSystem = mkSecureFileSystem pkgs;
    in
    pkgs.replaceVarsWith {
      name = "local-control-environment-snapshot";
      src = ./scripts/environment-snapshot.sh;
      dir = "bin";
      isExecutable = true;
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
    pkgs.replaceVarsWith {
      name = "local-control-source-snapshot";
      src = ./scripts/source-tree-snapshot.sh;
      dir = "bin";
      isExecutable = true;
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
      sourceIdentity = pkgs.replaceVarsWith {
        name = "local-control-source-identity";
        src = ./scripts/source-identity.sh;
        dir = "bin";
        isExecutable = true;
        replacements = {
          bash = "${pkgs.bash}/bin/bash";
          secureFileSystem = "${secureFileSystem}/bin/local-control-secure-files";
          git = "${pkgs.git}/bin/git";
          sha256sum = "${pkgs.coreutils}/bin/sha256sum";
          cut = "${pkgs.coreutils}/bin/cut";
        };
      };
    in
    pkgs.replaceVarsWith {
      name = "local-control-preparation-proof";
      src = ./scripts/preparation-proof.sh;
      dir = "bin";
      isExecutable = true;
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
    pkgs.replaceVarsWith {
      name = "local-control-private-path";
      src = ./scripts/private-path-guard.sh;
      dir = "bin";
      isExecutable = true;
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
    pkgs.replaceVarsWith {
      name = "local-control-service-gate";
      src = ./scripts/preparation-gate.sh;
      dir = "bin";
      isExecutable = true;
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
    pkgs.replaceVarsWith {
      name = "local-control-validate-database-cluster";
      src = ./scripts/database-cluster-validator.sh;
      dir = "bin";
      isExecutable = true;
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
}
