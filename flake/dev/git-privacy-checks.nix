{ self, inputs, ... }: {
  perSystem = { pkgs, ... }: {
    checks.git-email-privacy =
      let
        desktop = self.nixosConfigurations.desktop.config.home-manager.users.ianmh;
        macbook = self.darwinConfigurations.macbook-pro-m4.config.home-manager.users.ianmh;
        safeIdentity =
          home:
          !(home.programs.git.settings.user ? email)
          && home.programs.git.settings.user.useConfigOnly
          &&
            map (entry: entry.path) home.programs.git.includes == [
              home.nixSeal.templates.gitconfig-username.path
              home.nixSeal.templates.gitconfig-useremail-github.path
            ]
          && home.nixSeal.templates.jujutsu-identity.placeholders.email.secret == "git-user-email-github";
        # The reusable feature must evaluate without an owner's profile or nix-seal.
        generic =
          (inputs.home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              ../../modules/home/dev/git-privacy.nix
              {
                home = {
                  username = "fixture";
                  homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/fixture" else "/home/fixture";
                  stateVersion = "25.11";
                };
                programs.git = {
                  enable = true;
                  emailPrivacy = {
                    enable = true;
                    policyFile = "/runtime/private-policy.json";
                  };
                };
              }
            ];
          }).config;
        home = if pkgs.stdenv.hostPlatform.isDarwin then macbook else desktop;
        nativeChecks =
          cfg:
          !(cfg.programs.git.settings.core or { } ? hooksPath)
          &&
            builtins.attrNames cfg.programs.git.settings.hook == [
              "email-privacy-commit"
              "email-privacy-push"
            ]
          && cfg.programs.git.settings.hook.email-privacy-commit.event == "commit-msg"
          && cfg.programs.git.settings.hook.email-privacy-push.event == "pre-push";
      in
      assert safeIdentity desktop;
      assert safeIdentity macbook;
      assert nativeChecks desktop;
      assert nativeChecks macbook;
      assert nativeChecks generic;
      pkgs.runCommand "git-email-privacy"
        {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.git
          ];
          PRIVACY_COMMIT_COMMAND = home.programs.git.settings.hook.email-privacy-commit.command;
          PRIVACY_PUSH_COMMAND = home.programs.git.settings.hook.email-privacy-push.command;
        }
        ''
          mkdir -p modules/home/dev/scripts tests/git_privacy
          cp ${../../modules/home/dev/scripts/git-privacy-hook.py} modules/home/dev/scripts/git-privacy-hook.py
          cp ${../../tests/git_privacy/test_hooks.py} tests/git_privacy/test_hooks.py
          python3 -m unittest discover -s tests/git_privacy -v
          touch "$out"
        '';
  };
}
