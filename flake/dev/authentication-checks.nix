{ self, lib, ... }: {
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") (
      let
        host = self.nixosConfigurations.desktop.config;
        loginPam = pkgs.writeText "login.pam" host.security.pam.services.login.text;
        lockPam = pkgs.writeText "hyprlock.pam" host.security.pam.services.hyprlock.text;
      in
      {
        desktop-authentication =
          pkgs.runCommand "desktop-authentication-policy" { nativeBuildInputs = [ pkgs.gnugrep ]; }
            ''
              for pam in ${loginPam} ${lockPam}; do
                ! grep -Eq '^auth .*nullok' "$pam"
                grep -Eq '^auth .*pam_deny[.]so' "$pam"
              done
              touch "$out"
            '';
      }
    );
  };
}
