{ pkgs, ... }: {
  reason = "MicroSocks accepts authentication only through argv, exposing decrypted systemd credentials during process startup.";
  upstream = "https://github.com/rofl0r/microsocks/blob/v1.0.5/sockssrv.c";
  removal = "Upstream supports private username/password files and passes the credential-file authentication regression.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        supportsCredentialFiles = true;
      };
      patches = (old.patches or [ ]) ++ [ ./patches/microsocks-credential-files.patch ];
      nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [
        (pkgs.python3.withPackages (_: [
          (import ../../lib/python/notification-process/package.nix { inherit pkgs; })
        ]))
      ];
      doCheck = true;
      checkPhase = (import ../../lib/templates/text.nix) ./scripts/check-microsocks-credential-files.sh {
        tests_microsocks_credential_files_py = ./tests/microsocks_credential_files.py;
      };
    });
}
