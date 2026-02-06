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
      inherit settings;
    };

  darwin =
    { lib, config, ... }:
    let
      settings = sharedSettings // {
        trusted-users = [ "@admin" ];
      };
    in
    lib.mkMerge [
      (lib.mkIf (config.nix.enable) { nix = { inherit settings; }; })
      (lib.mkIf (lib.hasAttr "determinateNix" config) {
        determinateNix.customSettings = settings;
      })
    ];

  homeManager =
    { lib, pkgs, ... }:
    {
      nix.package = lib.mkDefault pkgs.nix;
      settings = sharedSettings;
    };
}
