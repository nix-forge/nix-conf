{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  title = "~literal $HOME \"quotes\" \\ backslash\nsecond line";
  status = "literal ; set -g @injected bad # comment";
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ../../modules/home/shells/tmux.nix
      {
        home = {
          username = "tester";
          homeDirectory = "/home/tester";
          stateVersion = "26.05";
        };
        programs.tmux.declarative = {
          titleFormat = title;
          status.leftFormat = status;
          status.interval = 17;
        };
      }
    ];
  };
in
pkgs.runCommand "tmux-config-contract"
  {
    nativeBuildInputs = [
      pkgs.tmux
      pkgs.python3
    ];
    configuration = home.config.xdg.configFile."tmux/tmux.conf".source;
    expected = builtins.toJSON { inherit title status; };
    passAsFile = [ "expected" ];
  }
  (
    (import ../../lib/templates/text.nix) ./scripts/check-tmux-config.sh {
      checkScript = ./scripts/check_tmux_config.py;
      holdCommand = lib.getExe' pkgs.coreutils "cat";
    }
  )
