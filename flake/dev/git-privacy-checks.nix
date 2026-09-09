{ self, ... }: {
  perSystem = { pkgs, ... }: {
    checks.git-email-privacy =
      let
        desktop = self.nixosConfigurations.desktop.config.home-manager.users.ianmh;
        macbook = self.darwinConfigurations.macbook-pro-m4.config.home-manager.users.ianmh;
        safeIdentity =
          home:
          home.programs.git.settings.user.email == "72767437+IanHollow@users.noreply.github.com"
          && home.programs.git.settings.user.useConfigOnly
          &&
            map (entry: entry.path) home.programs.git.includes
            == [ home.nixSeal.templates.gitconfig-username.path ]
          && home.nixSeal.templates.jujutsu-identity.placeholders.email.secret == "git-user-email-github";
      in
      assert safeIdentity desktop;
      assert safeIdentity macbook;
      pkgs.runCommand "git-email-privacy"
        {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.git
          ];
          hooks =
            (if pkgs.stdenv.hostPlatform.isDarwin then macbook else desktop)
            .programs.git.settings.core.hooksPath;
        }
        ''
          mkdir -p modules/home/dev/scripts tests/git_privacy
          cp ${../../modules/home/dev/scripts/git-privacy-hook.py} modules/home/dev/scripts/git-privacy-hook.py
          cp ${../../tests/git_privacy/test_hooks.py} tests/git_privacy/test_hooks.py
          for hook in pre-commit commit-msg pre-push post-checkout pre-receive; do
            test -x "$hooks/$hook"
          done
          python3 -m unittest discover -s tests/git_privacy -v
          touch "$out"
        '';
  };
}
