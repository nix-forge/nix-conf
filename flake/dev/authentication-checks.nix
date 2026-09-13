{ self, lib, ... }: {
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") (
      let
        host = self.nixosConfigurations.desktop.config;
        home = host.home-manager.users.ianmh;
        toml = pkgs.formats.toml { };
        manifest = pkgs.writeText "desktop-authentication-files.json" (
          builtins.toJSON {
            greeter = toml.generate "greeter.toml" host.services.displayManager.noctalia-greeter.settings;
            greetd = toml.generate "greetd.toml" host.services.greetd.settings;
            lock = home.xdg.configFile."hypr/hyprlock.conf".source;
            idle = home.xdg.configFile."hypr/hypridle.conf".source;
            shell = home.xdg.configFile."noctalia/config.toml".source;
            loginPam = pkgs.writeText "login.pam" host.security.pam.services.login.text;
            lockPam = pkgs.writeText "hyprlock.pam" host.security.pam.services.hyprlock.text;
          }
        );
      in
      {
        desktop-authentication =
          assert lib.all (entry: entry.assertion) host.assertions;
          assert lib.all (entry: entry.assertion) home.assertions;
          assert !host.services.fprintd.enable;
          pkgs.runCommand "desktop-authentication-policy" { } ''
            ${pkgs.python3}/bin/python ${../../tests/nix/check-desktop-authentication.py} ${manifest}
            mkdir "$out"
            cp ${manifest} "$out/manifest.json"
          '';
      }
    );
  };
}
