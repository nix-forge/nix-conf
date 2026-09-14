# Build the same behavioral probe into upstream and patched Sentry packages.
{ python3 }:
package:
package.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python3 ];
  postPatch = (old.postPatch or "") + ''
    cp ${./crashpad-lock.cc} nix-conf-crashpad-lock.cc
    cat >> CMakeLists.txt <<'CMAKE'
    add_executable(nix-conf-crashpad-lock-test nix-conf-crashpad-lock.cc)
    target_link_libraries(nix-conf-crashpad-lock-test PRIVATE crashpad_client crashpad_interface)
    target_compile_options(nix-conf-crashpad-lock-test PRIVATE
      -Wall -Wextra -Wpedantic -Werror
      # Crashpad's abstract interface has intentionally unused default
      # parameters. Keep that vendor warning visible without making it fatal.
      -Wno-error=unused-parameter)
    CMAKE
  '';
  postBuild = (old.postBuild or "") + ''
    LC_ALL=C ${python3}/bin/python3 ${./crashpad-lock.py} ./nix-conf-crashpad-lock-test
  '';
})
