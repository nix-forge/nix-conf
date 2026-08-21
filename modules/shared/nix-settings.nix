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
      hasNixAccessTokens = lib.hasAttrByPath [ "nixSeal" "secrets" nixAccessTokensId ] config;
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
        extraOptions = lib.mkIf hasNixAccessTokens ''
          !include ${config.nixSeal.secrets.${nixAccessTokensId}.path}
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
      hasNixAccessTokens = lib.hasAttrByPath [ "nixSeal" "secrets" nixAccessTokensId ] config;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) {
        nix = {
          package = lib.mkDefault pkgs.nixVersions.latest;
          optimise.automatic = lib.mkDefault true;
          channel.enable = lib.mkDefault false;
          inherit settings;
          extraOptions = lib.mkIf hasNixAccessTokens ''
            !include ${config.nixSeal.secrets.${nixAccessTokensId}.path}
          '';
        };
      })
      (lib.mkIf usingDeterminateNix {
        determinateNix.customSettings = determinateSettings;
        environment.etc."nix/nix.custom.conf".text = lib.mkIf hasNixAccessTokens (
          lib.mkAfter ''
            !include ${config.nixSeal.secrets.${nixAccessTokensId}.path}
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
      hasNixAccessTokens = lib.hasAttrByPath [ "nixSeal" "secrets" nixAccessTokensId ] config;
    in
    {
      nix = {
        package = lib.mkDefault pkgs.nixVersions.latest;
        # Daemon authorization is intentionally system-level. Home Manager
        # configures only client-safe settings, so a user cannot grant themself
        # daemon access or trusted-user privileges.
        settings = lib.mkIf (config.nix.package != null) sharedSettings;
        extraOptions = lib.mkIf (config.nix.package != null && hasNixAccessTokens) ''
          !include ${config.nixSeal.secrets.${nixAccessTokensId}.path}
        '';
      };
    };
}
