_: {
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        application-recovery = import ../../tests/recovery/application-recovery.nix { inherit pkgs; };
      };
    };
}
