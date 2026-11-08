_: {
  reason = "Actual sync server logs bank credentials in debug mode and OAuth callback queries in request and error paths.";
  upstream = "https://github.com/actualbudget/actual/blob/v26.10.0/packages/sync-server/src/services/secrets-service.js";
  removal = "The upstream sync server omits secret values and authentication URL queries from all affected logs.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/actual-redact-secret-log.patch ];
    });
}
