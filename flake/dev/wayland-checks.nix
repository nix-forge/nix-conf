{ self, ... }: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        desktop-wayland-environment =
          let
            desktop = self.nixosConfigurations.desktop.config;
            user = desktop.home-manager.users.ianmh;
            sessionEnvironment = user.xdg.configFile."uwsm/env".source;
          in
          pkgs.runCommand "desktop-wayland-environment-check" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
            wayland_env=${sessionEnvironment}

            # Wayland-first defaults for the toolkits used by this desktop.
            grep -Fx 'export NIXOS_OZONE_WL=1' "$wayland_env"
            grep -Fx 'export GDK_BACKEND=wayland,x11,*' "$wayland_env"
            grep -Fx 'export SDL_VIDEODRIVER=wayland,x11,windows' "$wayland_env"
            grep -Fx 'export CLUTTER_BACKEND=wayland' "$wayland_env"
            grep -Fx "export QT_QPA_PLATFORM='wayland;xcb'" "$wayland_env"
            grep -Fx 'export MOZ_ENABLE_WAYLAND=1' "$wayland_env"

            # Keep the Wayland selection at session scope. Applications
            # should inherit the home/system environment instead of
            # duplicating or overriding it in individual desktop entries.
            touch "$out"
          '';
      };
    };
}
