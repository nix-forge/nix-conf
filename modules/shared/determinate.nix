let
  settings = {
    eval-cores = 0;
    lazy-trees = true;
  };
in
{
  nixos =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.determinate.nixosModules.default ];

      # NixOS exposes the Determinate integration as `determinate`, whereas
      # nix-darwin calls the corresponding option `determinateNix`.
      determinate.enable = true;

      nix = {
        inherit settings;
        # The upstream module selects its flake input directly. Use this
        # repository's overlaid package for both the CLI and Nixd's --nix-bin.
        # The priority override can go once upstream defaults to pkgs.nix or
        # exposes a separate package option.
        package = lib.mkForce pkgs.nix;
      };

      # Determinate Nixd is the Nix daemon on NixOS and owns garbage
      # collection.  Keep its documented default explicit so host modules do
      # not add a competing `nix.gc` or `nix-collect-garbage` schedule.
      environment.etc."determinate/config.json".text = builtins.toJSON {
        garbageCollector.strategy = "automatic";
      };

    };

  darwin =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isAarch64;
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
