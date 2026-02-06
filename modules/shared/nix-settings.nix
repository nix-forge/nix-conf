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
    let
      settings = sharedSettings // {
        trusted-users = [
          "@wheel"
          "@sudo"
          "nix-builder"
        ];

        extra-experimental-features = [
          "cgroups"
          "auto-allocate-uids"
        ];

        auto-allocate-uids = true;
        use-cgroups = true;
      };
    in
    {
      nix = { inherit settings; };
    };

  darwin =
    { lib, config, ... }:
    let
      settings = sharedSettings // {
        trusted-users = [ "@admin" ];
      };
      usingDeterminateNix = lib.hasAttr "determinateNix" config && config.determinateNix.enable;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) { nix = { inherit settings; }; })
      (lib.mkIf usingDeterminateNix { determinateNix.customSettings = settings; })
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
      };
    };
}
