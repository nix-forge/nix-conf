{
  inputs,
  lib,
  pkgs,
  specialArgs,
  ...
}:
let
  emulated =
    (specialArgs.buildSystem or pkgs.stdenv.buildPlatform.system) != pkgs.stdenv.hostPlatform.system;
  fixes = import ../../../../overlays/temporary { inherit inputs pkgs; };
in
{
  nixSeal = {
    # Non-native deployment callers execute this native ARM package under QEMU.
    # Keep its complete suite except the reproduced re-exec signal fixture;
    # native configurations retain the unmodified upstream package and tests.
    package = lib.mkIf emulated (
      fixes.apply "nix-seal-emulated-sigchld-tests" inputs.nix-seal.packages.aarch64-linux.nix-seal
    );
    secretDirectory = "hosts/nixos/raspberry-pi/local/secrets";
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./nix-seal/identity.pub);
    # This target-specific ciphertext contains the same DNS-only credential as
    # the desktop copy. Rekey this target after the credential is rotated.
    secrets.cloudflare-dns-token.phase = "services";
    secrets.homebridge-ui-username = {
      phase = "services";
      restartUnits = [ "homebridge.service" ];
    };
    secrets.homebridge-ui-password = {
      phase = "services";
      restartUnits = [ "homebridge.service" ];
    };
    secrets.scrypted-ui-username = {
      phase = "services";
      restartUnits = [ "scrypted.service" ];
    };
    secrets.scrypted-ui-password = {
      phase = "services";
      restartUnits = [ "scrypted.service" ];
    };
  };
}
