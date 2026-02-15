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

    extra-experimental-features = [
      "nix-command"
      "flakes"

      "repl-flake"
      "fetch-closure"
      "recursive-nix"
      "ca-derivations"
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
      settings = sharedSettings // {
        trusted-users = sharedSettings.trusted-users ++ [
          "@wheel"
          "@sudo"
          "nix-builder"
        ];

        extra-experimental-features = sharedSettings.extra-experimental-features ++ [
          "cgroups"
          "auto-allocate-uids"
        ];

        auto-allocate-uids = true;
        use-cgroups = true;
      };
    in
    {
      nix = {
        package = lib.mkDefault pkgs.nixVersions.latest;
        channel.enable = lib.mkDefault false;
        inherit settings;
        extraOptions = lib.mkIf (lib.hasAttr "age" config) ''
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
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) {
        nix = {
          package = lib.mkDefault pkgs.nixVersions.latest;
          optimise.automatic = lib.mkDefault true;
          channel.enable = lib.mkDefault false;
          inherit settings;
          extraOptions = lib.mkIf (lib.hasAttr "age" config) ''
            !include ${config.age.secrets.nix-access-tokens.path}
          '';
        };
      })
      (lib.mkIf usingDeterminateNix {
        determinateNix.customSettings = settings;
        environment.etc."nix/nix.custom.conf".text = lib.mkIf (lib.hasAttr "age" config) (
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
    {
      nix = {
        package = lib.mkDefault pkgs.nixVersions.latest;
        settings = lib.mkIf (config.nix.package != null) sharedSettings;
        extraOptions = lib.mkIf (config.nix.package != null && lib.hasAttr "age" config) ''
          !include ${config.age.secrets.nix-access-tokens.path}
        '';
      };
    };
}
