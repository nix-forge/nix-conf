{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.feishin;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  settingsFile =
    if isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/feishin/config.json"
    else
      "${config.xdg.configHome}/feishin/config.json";
  finalMpvPackage = config.programs.mpv.finalPackage or null;
  mpvPackage =
    if finalMpvPackage == null then
      pkgs.mpv-unwrapped
    else
      finalMpvPackage.unwrapped or finalMpvPackage;
  mpvBinary = lib.getExe mpvPackage;
  # mpv publishes macOS Now Playing itself. The source badge comes from the
  # bundle containing its executable, so use a Feishin-branded copy of that
  # bundle for Feishin's private mpv child.
  darwinMpvBundle =
    pkgs.runCommand "feishin-mpv-bundle"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.rcodesign
        ];
      }
      (
        (import ../../lib/templates/text.nix) ./feishin-assets/build-mpv-bundle.sh {
          config_programs_mpv_finalPackage_unwrapped = mpvPackage;
          lib_escapeShellArg_mpvBinary = lib.escapeShellArg mpvBinary;
          pkgs_feishin = pkgs.feishin;
          scripts_feishin_check_py = ./feishin-assets/configure_mpv_bundle.py;
          lib_getExe_pkgs_rcodesign = lib.getExe pkgs.rcodesign;
        }
      );
  feishinMpv =
    if isDarwin then
      "${darwinMpvBundle}/Applications/Feishin mpv.app/Contents/MacOS/mpv"
    else
      pkgs.writeShellScript "feishin-mpv" (
        (import ../../lib/templates/text.nix) ./feishin-assets/feishin-mpv.sh {
          lib_escapeShellArg_mpvBinary = lib.escapeShellArg mpvBinary;
        }
      );
  # Home Manager's wrapped mpv explicitly loads every configured script,
  # including mpv-mpris. Feishin already publishes its own MPRIS player.
  mpvPath = "${dirOf settingsFile}/mpv";
  managedSettings = builtins.toJSON (
    {
      mpv_path = mpvPath;
    }
    // lib.optionalAttrs (cfg.managedLogin != null) {
      managed_login = {
        inherit (cfg.managedLogin) name url;
        username_path = cfg.managedLogin.usernameFile;
        password_path = cfg.managedLogin.passwordFile;
      };
    }
  );
  darwinApp = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Feishin.app";
in
{
  options.programs.feishin.managedLogin = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.nonEmptyStr;
            default = "Music";
            description = "Server display name.";
          };
          url = lib.mkOption {
            type = lib.types.strMatching "https?://.+";
            description = "Navidrome server URL.";
          };
          usernameFile = lib.mkOption {
            type = lib.types.str;
            description = "Absolute runtime file containing the server username.";
          };
          passwordFile = lib.mkOption {
            type = lib.types.str;
            description = "Absolute runtime file containing the server password.";
          };
        };
      }
    );
    default = null;
    description = "Optional managed Navidrome login. Credentials remain in runtime files outside the Nix store.";
  };

  config = {
    home.packages = [ pkgs.feishin ];
    programs.mpv.enable = lib.mkDefault true;
    targets.darwin.copyApps.enable = lib.mkIf isDarwin (lib.mkDefault true);

    # Keep Feishin's mpv link with its application data, outside the user profile.
    # Home Manager updates the link to the selected binary on each activation.
    xdg.configFile."feishin/mpv" = lib.mkIf (!isDarwin) {
      source = feishinMpv;
      force = true;
    };
    home.file."Library/Application Support/feishin/mpv" = lib.mkIf isDarwin {
      source = feishinMpv;
      force = true;
    };

    # Feishin's first-run migration clears config.json. Keep policy separate
    # from its mutable preferences and read it after migrations on every launch.
    xdg.configFile."feishin/managed.json" = lib.mkIf (!isDarwin) { text = managedSettings; };
    home.file."Library/Application Support/feishin/managed.json" = lib.mkIf isDarwin {
      text = managedSettings;
    };

    assertions = [
      {
        assertion =
          cfg.managedLogin == null
          ||
            lib.all
              (
                path:
                lib.hasPrefix "/" path
                && !lib.hasPrefix "/nix/store" path
                && !lib.elem ".." (lib.splitString "/" path)
              )
              [
                cfg.managedLogin.usernameFile
                cfg.managedLogin.passwordFile
              ];
        message = "Feishin managed login credentials must use absolute runtime paths outside the Nix store.";
      }
      {
        assertion = config.programs.mpv.enable && finalMpvPackage != null;
        message = "Feishin's local player requires programs.mpv.enable.";
      }
      {
        assertion = !isDarwin || config.targets.darwin.copyApps.enable;
        message = "Feishin on macOS requires a copied app bundle for LaunchServices.";
      }
    ];

    home.activation = {
      registerFeishinDarwinApp = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "copyApps" ] (
          (import ../../lib/templates/text.nix) ./feishin-assets/register-app.sh {
            lib_escapeShellArg_darwinApp = lib.escapeShellArg darwinApp;
          }
        )
      );

      registerFeishinMpvApp = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "copyApps" ] (
          (import ../../lib/templates/text.nix) ./feishin-assets/register-mpv-bundle.sh {
            lib_escapeShellArg_darwinMpvBundle_Applications_Feishin_mpv_ = lib.escapeShellArg "${darwinMpvBundle}/Applications/Feishin mpv.app";
          }
        )
      );
    };
  };
}
