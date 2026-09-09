{ pkgs, ... }: {
  reason = "Crashpad logs expected interprocess report-lock contention as a filesystem error.";
  upstream = "https://github.com/getsentry/crashpad/blob/e5040b878718f5c004d0ecfe1747642c72ddcd39/client/crash_report_database_generic.cc#L112-L121";
  removal = "Unmodified Determinate Sentry passes the pending/completed contention and real-error regression checks.";
  reviewedRevision = "3ed5caa3bbde51ab87977c8a80e27c6ed0ea8534";
  inputPath = [
    "determinate"
    "inputs"
    "nix"
  ];
  apply =
    package:
    let
      patched = package.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          bash ${./patches/apply-crashpad-lock.sh} ${./patches/sentry-crashpad-lock.patch}
        '';
      });
    in
    patched.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        tests = (old.passthru.tests or { }) // {
          crashpad-lock = import ./tests/crashpad-lock.nix { inherit (pkgs) python3; } patched;
        };
      };
    });
}
