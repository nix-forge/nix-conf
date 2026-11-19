_: {
  reason = "MicroSocks accepts authentication only through argv, exposing decrypted systemd credentials during process startup.";
  upstream = "https://github.com/rofl0r/microsocks/blob/v1.0.5/sockssrv.c";
  removal = "Upstream supports private username/password files and passes the credential-file authentication regression.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        supportsCredentialFiles = true;
      };
      patches = (old.patches or [ ]) ++ [ ./patches/microsocks-credential-files.patch ];
    });
}
