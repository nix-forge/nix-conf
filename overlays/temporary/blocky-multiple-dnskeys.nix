_: {
  reason = "Blocky selects only the first DS-matched DNSKEY and rejects valid zones when another trusted key signs the DNSKEY RRset.";
  upstream = "https://github.com/0xERR0R/blocky/pull/2293";
  removal = "The selected Blocky source includes ef95d592b323a06ad95ce10daeb53b534a8a8e79 and passes the multiple-key and verification-limit regressions without this patch.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "0.35.0";
    until = "0.35.1";
  };
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/blocky-multiple-dnskeys.patch ];
      patchFlags = (old.patchFlags or [ "-p1" ]) ++ [ "--fuzz=0" ];
      # The full upstream suite needs network access. This validator suite
      # uses local fixtures and retains the upstream cryptographic regressions.
      doCheck = true;
      checkPhase = ''
        runHook preCheck
        go test -p "$NIX_BUILD_CORES" ./resolver/dnssec
        runHook postCheck
      '';
    });
}
