{ pkgs, lib, ... }: {
  reason = "Rift does not count unbound keyboard activity as user input after wake or unlock, leaving native app switching suppressed.";
  upstream = "https://github.com/acsandmann/rift/blob/2bb6647a18cde9ac44470d296988298c1093460d/src/actor/reactor.rs";
  removal = "The selected unpatched source recognizes native keyboard interaction after wake/unlock and passes the native Command+Tab reproduction.";
  reviewedRevision = "1d060086d60cb76a40cf37109f979d88a5bd6396";
  inputPath = [ "nixpkgs" ];
  packageName = "rift";
  affectedVersions = {
    from = "0.7.2";
    until = "0.7.3";
  };
  apply =
    package:
    assert package.unwrapped.src.rev == "2bb6647a18cde9ac44470d296988298c1093460d";
    package.override {
      rustPlatform = pkgs.rustPlatform // {
        buildRustPackage =
          args:
          pkgs.rustPlatform.buildRustPackage (
            args
            // {
              patches = (args.patches or [ ]) ++ [ ./patches/rift-native-app-switch.patch ];
              # Run the new reactor guard test without synthetic screen fixtures.
              # Keep the session-dependent reactor gesture cases excluded: the
              # actor::gesture:: filter also matches reactor::gesture::.
              checkFlags = (lib.filter (flag: flag != "--skip=actor::reactor::") args.checkFlags) ++ [
                "--skip=actor::reactor::gesture::"
                "actor::reactor::tests::native_keyboard_input_clears_resume_guard_without_changing_focus_or_layout"
              ];
            }
          );
      };
    };
}
