{ pkgs, ... }: {
  reason = "Rift 0.8.3 counts held-key autorepeats as fresh keyboard intent after wake or unlock.";
  upstream = "https://github.com/acsandmann/rift/blob/23d52b5a36df2597e2880ca243061445d989f5b4/src/actor/input.rs";
  removal = "The selected unpatched source excludes synthetic keyboard events and autorepeats from fresh intent; native wake/unlock and Command+Tab acceptance pass.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  packageName = "rift";
  affectedVersions = {
    from = "0.8.3";
    until = "0.8.4";
  };
  apply =
    package:
    if package.unwrapped.src.rev != "23d52b5a36df2597e2880ca243061445d989f5b4" then
      throw "Invalid production input in rift-keyboard-repeat-intent.nix"
    else
      package.override {
        rustPlatform = pkgs.rustPlatform // {
          buildRustPackage =
            args:
            pkgs.rustPlatform.buildRustPackage (
              args // { patches = (args.patches or [ ]) ++ [ ./patches/rift-keyboard-repeat-intent.patch ]; }
            );
        };
      };
}
