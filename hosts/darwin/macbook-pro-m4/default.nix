{ modules, inputs, ... }: {
  system = "aarch64-darwin";
  hostName = "Ian-MBP";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJTE/d4MlNXECP5e/1Gi1u0so7wdoy1XtDotVE27P2rZ";
  };

  nixpkgsArgs = {
    overlays = [
      inputs.nixpkgs-personal.overlays.default
      (final: prev: {
        # @napi-rs/cli probes Darwin system identity while taking a temporary
        # build lock. Those probes are unnecessary for a single Nix build and
        # denied by the strict Darwin sandbox. Return an intentionally
        # incomplete identity so the lock falls back to its safe PID-based
        # handling, without weakening sandbox policy.
        oxlint = prev.oxlint.overrideAttrs (old: {
          preBuild =
            (old.preBuild or "")
            + final.lib.optionalString final.stdenv.hostPlatform.isDarwin ''
              for cli in node_modules/.pnpm/@napi-rs+cli@*/node_modules/@napi-rs/cli/dist/cli.js; do
                substituteInPlace "$cli" \
                  --replace-fail \
                  'if (process.platform === "darwin") {' \
                  'if (process.platform === "darwin") return { boot: null, bootSession: null, machine: null, namespace: null }; if (process.platform === "darwin") {'
              done
            '';
        });
      })
    ];
    config = {
      allowUnfree = true;
    };
  };

  modules = with modules; [
    { system.primaryUser = "ianmh"; }
    # Original nix-darwin compatibility generation for this installation.
    # Raising this is a migration decision, not a routine upgrade.
    { system.stateVersion = 6; }

    ## Base
    determinate
    nix-settings
    registry
    cache
    chromium-policies
    nixSeal
    ./nix-seal.nix
    ./local/firewall.nix

    security
    stylix
    fonts
  ];

  homes.ianmh = {
    config = "ianmh@macbook-pro-m4";
    user = {
      description = "Ian Holloway";
      shell = inputs.nixpkgs.legacyPackages.aarch64-darwin.nushell;
    };
  };
}
