let
  settings = {
    eval-cores = 0;
    lazy-trees = true;
  };
in
{
  nixos = { inputs, system, ... }: {
    imports = [ inputs.determinate.nixosModules.default ];

    nix = { inherit settings; };

    nixpkgs.overlays = [
      (_final: _prev: { nix = inputs.determinate.inputs.nix.packages.${system}.default; })
    ];
  };

  darwin =
    {
      inputs,
      lib,
      pkgs,
      system,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isAarch64;
      # Determinate Nix 3.21.1 includes functional tests that require local
      # networking and Crashpad Mach ports, both denied by the Darwin sandbox.
      # Keep using Determinate Nix everywhere, but temporarily omit its combined
      # functional-test build gate on Darwin.
      determinateNixPackage =
        inputs.determinate.inputs.nix.packages.${system}.default.overrideAttrs
          (_old: {
            doCheck = false;
          });
    in
    {
      imports = [ inputs.determinate.darwinModules.default ];

      assertions = [
        {
          assertion = isAarch64;
          message = "Determinate Nix on Darwin only supports aarch64 (Apple Silicon)";
        }
      ];

      determinateNix = {
        enable = true;

        determinateNixd = {
          builder.state = "enabled";
          garbageCollector.strategy = "automatic";
        };

        customSettings = settings;
      };

      # Determinate Nixd owns the Nix daemon and its socket on Darwin.  The
      # legacy multi-user installer plist is unmanaged once `nix.enable` is
      # disabled, so nix-darwin intentionally preserves it.  Remove that
      # redundant daemon after its activation step has completed.
      system.activationScripts.postActivation.text = lib.mkAfter ''
        legacyNixDaemonPlist=/Library/LaunchDaemons/org.nixos.nix-daemon.plist
        determinateNixDaemonPlist=/Library/LaunchDaemons/systems.determinate.nix-daemon.plist

        if [ -e "$legacyNixDaemonPlist" ] && [ -e "$determinateNixDaemonPlist" ]; then
          launchctl bootout system/org.nixos.nix-daemon 2>/dev/null || true
          rm -f "$legacyNixDaemonPlist"
        fi
      '';

      nixpkgs.overlays = [ (_final: _prev: { nix = determinateNixPackage; }) ];
    };

  homeManager =
    { inputs, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
    in
    {
      assertions = [
        {
          assertion = (!isDarwin) || isAarch64;
          message = "Determinate Nix on Darwin only supports aarch64 (Apple Silicon)";
        }
      ];

      imports = [ inputs.determinate.homeManagerModules.default ];

      # Workaround: Disable HM manual to suppress Determinate Nix warning
      # about options.json referencing store paths without proper context.
      # Upstream issue: https://github.com/nix-community/home-manager/issues/7935
      manual.manpages.enable = false;
    };
}
