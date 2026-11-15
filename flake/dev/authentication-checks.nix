{ self, lib, ... }: {
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") (
      let
        host = self.nixosConfigurations.desktop.config;
        loginPam = pkgs.writeText "login.pam" host.security.pam.services.login.text;
        lockPam = pkgs.writeText "hyprlock.pam" host.security.pam.services.hyprlock.text;
      in
      {
        desktop-hyprlock-lifecycle = import ../../tests/hyprland/hyprlock-lifecycle.nix {
          inherit pkgs;
          hyprland = host.programs.hyprland.package;
          hyprlock = host.programs.hyprlock.package;
        };
        desktop-authentication =
          pkgs.runCommand "desktop-authentication-policy" { nativeBuildInputs = [ pkgs.gnugrep ]; }
            (
              (import ../../lib/templates/text.nix) ./scripts/desktop-authentication-policy.sh {
                inherit loginPam;
                inherit lockPam;
              }
            );
      }
    );
  };
}
