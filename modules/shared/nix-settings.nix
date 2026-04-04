let
  sharedSettings = {
    max-jobs = "auto";
    cores = 0;

    allowed-users = [ "*" ];

    trusted-users = [ "root" ];

    sandbox = true;
    sandbox-fallback = false;

    keep-derivations = true;
    keep-outputs = true;
    keep-going = true;

    connect-timeout = 5;
    fallback = true;

    log-lines = 25;

    warn-dirty = false;
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
      hasNixAccessTokens = lib.hasAttrByPath [ "age" "secrets" "nix-access-tokens" ] config;
      settings = sharedSettings // {
        trusted-users = sharedSettings.trusted-users ++ [
          "@wheel"
          "@sudo"
          "nix-builder"
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
          !include ${config.age.secrets.nix-access-tokens.path}
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
        trusted-users = sharedSettings.trusted-users ++ [ "@admin" ];
      };
      usingDeterminateNix = lib.hasAttr "determinateNix" config && config.determinateNix.enable;
      hasNixAccessTokens = lib.hasAttrByPath [ "age" "secrets" "nix-access-tokens" ] config;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) {
        nix = {
          package = lib.mkDefault pkgs.nixVersions.latest;
          optimise.automatic = lib.mkDefault true;
          channel.enable = lib.mkDefault false;
          inherit settings;
          extraOptions = lib.mkIf hasNixAccessTokens ''
            !include ${config.age.secrets.nix-access-tokens.path}
          '';
        };
      })
      (lib.mkIf usingDeterminateNix {
        determinateNix.customSettings = settings;
        environment.etc."nix/nix.custom.conf".text = lib.mkIf hasNixAccessTokens (
          lib.mkAfter ''
            !include ${config.age.secrets.nix-access-tokens.path}
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
      hasNixAccessTokens = lib.hasAttrByPath [ "age" "secrets" "nix-access-tokens" ] config;
    in
    {
      nix = {
        package = lib.mkDefault pkgs.nixVersions.latest;
        settings = lib.mkIf (config.nix.package != null) sharedSettings;
        extraOptions = lib.mkIf (config.nix.package != null && hasNixAccessTokens) ''
          !include ${config.age.secrets.nix-access-tokens.path}
        '';
      };
    };
}
