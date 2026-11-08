{
  config,
  lib,
  pkgs,
  myLib,
  ...
}:
let
  cfg = config.networking.wireless.iwd.runtimeProfiles;
  validator =
    pkgs.runCommandCC "validate-iwd-profile"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.ell ];
      }
      ''
        mkdir -p "$out/bin"
        $CC -std=c11 -Wall -Wextra -Werror ${./iwd-profiles-assets/validate-profile.c} \
          $(pkg-config --cflags --libs ell) -o "$out/bin/validate-iwd-profile"
      '';
  materializer = pkgs.writers.writePython3Bin "materialize-iwd-profile" {
    libraries = [ (myLib.python.notificationProcess { inherit pkgs; }) ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./iwd-profiles-assets/materialize_profile.py;
  runtimePath =
    path:
    lib.hasPrefix "/" path
    && !lib.hasPrefix "/nix/store" path
    && !lib.elem ".." (lib.splitString "/" path);
in
{
  key = "nix-conf/iwd-profiles/nixos";
  options.networking.wireless.iwd.runtimeProfiles = lib.mkOption {
    default = { };
    description = "Credential-backed native IWD profiles. Runtime source files begin with SSID=<network name>, followed by native IWD sections. SSIDs and credentials stay outside the store.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          source = lib.mkOption {
            type = lib.types.str;
            example = "/run/credentials/wifi-profile";
            description = "Absolute private runtime file, owned by root with no group or other access.";
          };
          profileType = lib.mkOption {
            type = lib.types.enum [
              "psk"
              "8021x"
              "open"
            ];
            default = "psk";
            description = "Native IWD network profile type.";
          };
          afterUnits = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Optional secret provisioning units. Soft dependencies retain last-known-good profiles on provisioning failure.";
          };
        };
      }
    );
  };
  config = lib.mkIf (cfg != { }) {
    networking.wireless.iwd.enable = lib.mkDefault true;
    assertions = [
      {
        assertion = lib.all (
          name:
          lib.all (
            unit:
            builtins.match "[-A-Za-z0-9_@:.]+[.][A-Za-z]+" unit != null
            && !lib.elem unit [
              "iwd.service"
              "iwd-${name}-profile.service"
            ]
          ) cfg.${name}.afterUnits
        ) (lib.attrNames cfg);
        message = "IWD profile afterUnits require native unit names and must not depend on IWD or the profile unit itself.";
      }
      {
        assertion = config.networking.wireless.iwd.enable;
        message = "IWD runtime profiles require networking.wireless.iwd.enable.";
      }
      {
        assertion = lib.all runtimePath (map (profile: profile.source) (lib.attrValues cfg));
        message = "IWD runtime profiles require absolute credential paths outside the Nix store.";
      }
      {
        assertion = lib.all (name: builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null) (
          lib.attrNames cfg
        );
        message = "IWD runtime profile identifiers must contain only letters, digits, underscores or hyphens.";
      }
    ];
    system.build.iwdProfileTools = pkgs.linkFarm "iwd-profile-tools" [
      {
        name = "materialize";
        path = lib.getExe materializer;
      }
      {
        name = "validate";
        path = lib.getExe' validator "validate-iwd-profile";
      }
    ];
    systemd.services = lib.mapAttrs' (
      name: profile:
      lib.nameValuePair "iwd-${name}-profile" {
        description = "Materialize a protected IWD profile";
        unitConfig.ConditionPathExists = lib.replaceStrings [ "%" ] [ "%%" ] profile.source;
        wantedBy = [ "iwd.service" ];
        wants = profile.afterUnits;
        partOf = [ "iwd.service" ] ++ profile.afterUnits;
        after = profile.afterUnits;
        before = [ "iwd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
          ExecStart = (import ../../../lib/systemd/exec-args.nix) [
            (lib.getExe materializer)
            profile.source
            "/var/lib/iwd"
            (lib.getExe' validator "validate-iwd-profile")
            profile.profileType
          ];
        };
      }
    ) cfg;
  };
}
