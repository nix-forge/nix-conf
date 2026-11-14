let
  sharedSettings = {
    max-jobs = "auto";
    cores = 0;

    sandbox = true;
    sandbox-fallback = false;

    keep-derivations = true;
    keep-outputs = false;
    keep-going = true;

    connect-timeout = 5;
    fallback = true;

    log-lines = 25;

    # A dirty configuration is useful during development but should never be
    # silently deployed as though it were a reproducible revision.
    warn-dirty = true;
    accept-flake-config = false;

    auto-optimise-store = true;

    experimental-features = [
      "nix-command"
      "flakes"

      "fetch-closure"
      "recursive-nix"
      "configurable-impure-env"

      "ca-derivations"
      "impure-derivations"

      "blake3-hashes"
    ];
  };
in
{
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nixAccessTokensId = "nix-access-tokens";
      runtimeFiles = (config.nixSeal.secrets or { }) // (config.nixSeal.templates or { });
      hasNixAccessTokens = builtins.hasAttr nixAccessTokensId runtimeFiles;
      settings = sharedSettings // {
        # Restrict daemon access to administrators without assuming a
        # particular account name. Root is trusted by Nix by default.
        allowed-users = [
          "@wheel"
          "@sudo"
        ];
        trusted-users = [
          "@wheel"
          "@sudo"
        ];

        experimental-features = sharedSettings.experimental-features ++ [
          "cgroups"
          "auto-allocate-uids"
        ];

        auto-allocate-uids = true;
        use-cgroups = true;

        system-features = [ "uid-range" ];
      };
    in
    {
      nix = {
        package = lib.mkDefault pkgs.nixVersions.latest;
        channel.enable = lib.mkDefault false;
        inherit settings;
      };
      # System-private credentials must never be included by public nix.conf:
      # an unreadable optional include discards its containing configuration.
      systemd.services.nix-daemon = lib.mkIf hasNixAccessTokens {
        after = [ "nix-seal-activate.service" ];
        environment.NIX_USER_CONF_FILES = "/root/.config/nix/nix.conf";
      };
      system.build.nixRootCredentials = lib.mkIf hasNixAccessTokens (
        pkgs.writeText "root-nix-credentials.conf" ''
          !include ${runtimeFiles.${nixAccessTokensId}.path}
        ''
      );
      system.activationScripts.nixRootCredentials = lib.mkIf hasNixAccessTokens {
        deps = [ "etc" ];
        text = ''
          ${pkgs.runtimeShell} ${./nix-settings-assets/install-root-credentials.sh} /root ${config.system.build.nixRootCredentials}
        '';
      };
    };

  darwin =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      settings = sharedSettings // {
        # macOS administrators are the only local users allowed to access the
        # daemon. This remains valid for every account on a host.
        allowed-users = [
          "root"
          "@admin"
        ];
        trusted-users = [
          "root"
          "@admin"
        ];
      };
      determinateSettings = settings // {
        min-free = 30 * 1024 * 1024 * 1024;
        max-free = 100 * 1024 * 1024 * 1024;
        gc-reserved-space = 1024 * 1024 * 1024;
      };
      usingDeterminateNix = lib.hasAttr "determinateNix" config && config.determinateNix.enable;
      nixAccessTokensId = "nix-access-tokens";
      runtimeFiles = (config.nixSeal.secrets or { }) // (config.nixSeal.templates or { });
      hasNixAccessTokens = builtins.hasAttr nixAccessTokensId runtimeFiles;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) {
        nix = {
          package = lib.mkDefault pkgs.nixVersions.latest;
          optimise.automatic = lib.mkDefault true;
          channel.enable = lib.mkDefault false;
          inherit settings;
        };
      })
      (lib.mkIf usingDeterminateNix { determinateNix.customSettings = determinateSettings; })
      (lib.mkIf hasNixAccessTokens {
        # The vendor-owned daemon plist is preserved. Root clients and a fresh
        # root daemon use the normal private root configuration search path.
        system.activationScripts.postActivation.text = lib.mkAfter (
          let
            credentials = pkgs.writeText "root-nix-credentials.conf" ''
              !include ${runtimeFiles.${nixAccessTokensId}.path}
            '';
          in
          ''
            ${pkgs.runtimeShell} ${./nix-settings-assets/install-root-credentials.sh} /var/root ${credentials}
          ''
        );
      })
    ];

  homeManager =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      nixAccessTokensId = "nix-access-tokens";
      runtimeFiles = (config.nixSeal.secrets or { }) // (config.nixSeal.templates or { });
      hasNixAccessTokens = builtins.hasAttr nixAccessTokensId runtimeFiles;
    in
    {
      # Determinate sets package = null on both platforms. Own only the private
      # user include in that branch; shared public settings remain system-owned.
      xdg.configFile."nix/nix.conf" = lib.mkIf (config.nix.package == null && hasNixAccessTokens) {
        text = ''
          !include ${runtimeFiles.${nixAccessTokensId}.path}
        '';
      };
      nix = {
        package = lib.mkDefault pkgs.nixVersions.latest;
        # Daemon authorization is intentionally system-level. Home Manager
        # configures only client-safe settings, so a user cannot grant themself
        # daemon access or trusted-user privileges.
        settings = lib.mkIf (config.nix.package != null) sharedSettings;
        extraOptions = lib.mkIf (config.nix.package != null && hasNixAccessTokens) ''
          !include ${runtimeFiles.${nixAccessTokensId}.path}
        '';
      };
    };
}
