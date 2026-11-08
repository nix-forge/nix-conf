{ pkgs, config }:
assert pkgs.lib.all (assertion: assertion.assertion) config.assertions;
pkgs.runCommand "public-darwin-generated-config"
  {
    nativeBuildInputs = [
      pkgs.zsh
      pkgs.python3
    ];
    zshrc = pkgs.writeText "public-example-zshrc" config.environment.etc."zshrc".text;
    plist = config.environment.launchDaemons."org.nix-community.public-example-health.plist".source;
  }
  (
    (import ./lib/render-text.nix) ./scripts/public-darwin-generated-config.sh {
      scripts_generated_config_check_py = ./scripts/generated_config_check.py;
    }
  )
