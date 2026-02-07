let
  sharedSettings = {
    max-jobs = "auto";
    cores = 0;

    allowed-users = [ "*" ];

    trusted-users = [ "root" ];

    sandbox = true;
    sandbox-fallback = false;

    keep-going = true;

    extra-experimental-features = [
      "nix-command"
      "flakes"
    ];

    warn-dirty = false;

    accept-flake-config = false;

    keep-derivations = true;
    keep-outputs = true;
  };
in
{
  nixos =
    { config, lib, ... }:
    let
      settings = sharedSettings // {
        trusted-users = [
          "root"
          "@wheel"
          "@sudo"
          "nix-builder"
        ];

        extra-experimental-features = [
          "nix-command"
          "flakes"
          "cgroups"
          "auto-allocate-uids"
        ];

        auto-allocate-uids = true;
        use-cgroups = true;
      };
    in
    {
      nix = {
        inherit settings;
        extraOptions = lib.mkIf (lib.hasAttr "age" config) ''
          !include ${config.age.secrets.nix-access-tokens.path}
        '';
      };
    };

  darwin =
    { lib, config, ... }:
    let
      settings = sharedSettings // {
        trusted-users = [
          "root"
          "@admin"
        ];
      };
      usingDeterminateNix = lib.hasAttr "determinateNix" config && config.determinateNix.enable;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) {
        nix = {
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
        package = lib.mkDefault pkgs.nix;
        settings = lib.mkIf (config.nix.package != null) sharedSettings;
        extraOptions = lib.mkIf (config.nix.package != null && lib.hasAttr "age" config) ''
          !include ${config.age.secrets.nix-access-tokens.path}
        '';
      };
    };
}
