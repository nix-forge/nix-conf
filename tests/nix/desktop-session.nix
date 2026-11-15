{
  inputs,
  pkgs,
  system ? pkgs.stdenv.hostPlatform.system,
}:
let
  inherit (pkgs) lib;
  environmentPath = "xdg/uwsm/env.d/10-session-class";
  configFor =
    modules:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = modules ++ [ { system.stateVersion = "26.05"; } ];
    }).config;
  desktops = {
    hyprland = ../../modules/nixos/desktop-envs/hyprland.nix;
    gnome = ../../modules/nixos/desktop-envs/gnome.nix;
    plasma = ../../modules/nixos/desktop-envs/plasma.nix;
    cosmic = ../../modules/nixos/desktop-envs/cosmic.nix;
  };
  native = lib.mapAttrs (_: module: configFor [ module ]) (removeAttrs desktops [ "hyprland" ]);
  managed = lib.mapAttrs (
    _: module:
    configFor [
      module
      { programs.uwsm.enable = true; }
    ]
  ) desktops;
  standalone = configFor [
    ../../modules/nixos/desktop-envs/session.nix
    { programs.uwsm.enable = true; }
  ];
  disabled = configFor [ ../../modules/nixos/desktop-envs/session.nix ];
  # Importing two consumers must still leave a single shared owner.
  combined = configFor [
    ../../modules/nixos/desktop-envs/hyprland.nix
    ../../modules/nixos/desktop-envs/interactive.nix
  ];
  sessionText = standalone.environment.etc.${environmentPath}.text;
in
assert !(disabled.environment.etc ? ${environmentPath});
assert lib.all (config: !(config.environment.etc ? ${environmentPath})) (
  builtins.attrValues native
);
assert lib.all (
  config:
  config.environment.etc.${environmentPath}.text == sessionText
  && !(config.environment.etc ? "xdg/uwsm/env-hyprland.d/10-session-class")
) (builtins.attrValues managed);
assert combined.environment.etc.${environmentPath}.text == sessionText;
pkgs.runCommand "desktop-session" { } (
  (import ../../lib/templates/text.nix) ./scripts/desktop-session.sh {
    pkgs_writeText_uwsm_session_class_sessionText = pkgs.writeText "uwsm-session-class" sessionText;
    pkgs_coreutils = pkgs.coreutils;
    pkgs_runtimeShell = pkgs.runtimeShell;
  }
)
