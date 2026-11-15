{ inputs, lib, ... }: {
  nixSeal = {
    # The desktop builds this ARM package under QEMU. A runtime SIGCHLD test
    # depends on host process semantics and fails in that emulator. Run the
    # package's full suite natively in CI; skip checks for this target build.
    package = inputs.nix-seal.packages.aarch64-linux.nix-seal.overrideAttrs (_: {
      doCheck = false;
    });
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
