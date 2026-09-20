{ inputs, ... }: {
  perSystem = { pkgs, ... }: {
    checks.git-email-privacy =
      let
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
      assert nativeChecks generic;
      (import ../../tests/python-check.nix { inherit pkgs; }) {
        name = "git-email-privacy";
        files = [
          ../../tests/git_privacy
          ../../modules/home/dev/scripts/git-privacy-hook.py
        ];
        testPaths = [ "tests/git_privacy" ];
        selection = "nix_integration";
        nativeBuildInputs = [ pkgs.git ];
        # Exercise the generated commands with this check's native package set.
        environment = {
          PRIVACY_COMMIT_COMMAND = generic.programs.git.settings.hook.email-privacy-commit.command;
          PRIVACY_PUSH_COMMAND = generic.programs.git.settings.hook.email-privacy-push.command;
        };
      };
  };
}
