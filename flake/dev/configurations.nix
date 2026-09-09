{ self, ... }: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      evaluations =
        kind: configurations: closureFor:
        lib.mapAttrs' (
          name: configuration:
          lib.nameValuePair "${kind}-configuration-${name}" (
            let
              configurationSystem = configuration.pkgs.stdenv.hostPlatform.system;
              native = configurationSystem == system;
              closure = closureFor configuration;
              drvPath =
                if native then
                  assert lib.isDerivation closure;
                  closure.drvPath
                else
                  null;
            in
            pkgs.runCommand "configuration-evaluation"
              {
                # Evaluation checks must never build the full system closure.
                report = builtins.unsafeDiscardStringContext (
                  builtins.toJSON {
                    inherit
                      kind
                      name
                      configurationSystem
                      native
                      drvPath
                      ;
                  }
                );
                passAsFile = [ "report" ];
              }
              ''
                cp "$reportPath" "$out"
              ''
          )
        ) configurations;
    in
    {
      checks =
        evaluations "nixos" (self.nixosConfigurations or { }) (
          configuration: configuration.config.system.build.toplevel
        )
        // evaluations "darwin" (self.darwinConfigurations or { }) (configuration: configuration.system);
    };
}
