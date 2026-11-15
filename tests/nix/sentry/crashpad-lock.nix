# Build the same behavioral probe into upstream and patched Sentry packages.
{
  python3,
  expectNoisyContention ? false,
}:
package:
package.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python3 ];
  postPatch =
    (old.postPatch or "")
    + ((import ../../../lib/templates/text.nix) ./scripts/add-crashpad-lock-source.sh {
      crashpad_lock_cc = ./crashpad-lock.cc;
      cmakeSource = ./scripts/crashpad-lock.cmake;
    });
  postBuild = (old.postBuild or "") + ''
    LC_ALL=C ${python3}/bin/python3 ${./crashpad_lock.py} ./nix-conf-crashpad-lock-test ${
      if expectNoisyContention then "--expect-noisy-contention" else ""
    }
  '';
})
