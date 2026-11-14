{
  pkgs,
  inputs,
  nix ? pkgs.nix,
}:
let
  inherit (pkgs) lib;
  modules = import ../../modules/shared/nix-settings.nix;
  secretPath = "/root-private/credentials.conf";
  userSecretPath = "/user-private/credentials.conf";
  fixture = path: { lib, ... }: {
    options.nixSeal.templates = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    config.nixSeal.templates.nix-access-tokens.path = path;
  };
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  evaluateSystem =
    if isDarwin then inputs.nix-darwin.lib.darwinSystem else inputs.nixpkgs.lib.nixosSystem;
  system = evaluateSystem {
    modules = [
      (if isDarwin then modules.darwin else modules.nixos)
      (fixture secretPath)
      {
        nixpkgs.pkgs = pkgs;
        nix = {
          package = nix;
          settings = {
            min-free = 214748364800;
            max-free = 268435456000;
          };
        };
        system.stateVersion = if isDarwin then 6 else "26.05";
      }
    ];
  };
  home =
    package:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        modules.homeManager
        (fixture userSecretPath)
        {
          home = {
            username = "fixture";
            homeDirectory = if isDarwin then "/Users/fixture" else "/home/fixture";
            stateVersion = "25.05";
          };
          nix = {
            package = lib.mkForce package;
            enable = package != null;
          };
        }
      ];
    };
  nullHome = (home null).config;
  ordinaryHome = (home nix).config;
  public = system.config.environment.etc."nix/nix.conf".source;
  script = ../../modules/shared/nix-settings-assets/install-root-credentials.sh;
in
assert !(lib.hasInfix secretPath system.config.nix.extraOptions);
assert
  if isDarwin then
    lib.hasInfix "/var/root" system.config.system.activationScripts.postActivation.text
    && lib.hasInfix (toString script) system.config.system.activationScripts.postActivation.text
  else
    system.config.systemd.services.nix-daemon.environment.NIX_USER_CONF_FILES
    == "/root/.config/nix/nix.conf";
assert lib.hasInfix userSecretPath nullHome.xdg.configFile."nix/nix.conf".text;
assert lib.hasInfix userSecretPath ordinaryHome.nix.extraOptions;
(pkgs.runCommand "nix-credential-loading"
  {
    nativeBuildInputs = [
      (lib.getBin nix)
      pkgs.python3
      pkgs.coreutils
    ];
  }
  (
    (import ../../lib/templates/text.nix) ./scripts/nix-credential-loading.sh {
      inherit public script;
      python = lib.getExe pkgs.python3;
      probe = ./scripts/check_nix_credentials.py;
    }
  )
)
