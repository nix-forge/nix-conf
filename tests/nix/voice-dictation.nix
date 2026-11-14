# Isolated Home Manager evaluation: unrelated host selectors are not inputs.
{
  system ? builtins.currentSystem,
  username ? "dictation-test",
  homeDirectory ? (if system == "aarch64-darwin" then "/Users/${username}" else "/home/${username}"),
}:
let
  flake = builtins.getFlake (toString ../..);
  pkgs = import flake.inputs.nixpkgs {
    inherit system;
    overlays = [
      (
        final: prev:
        prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
          handy =
            (import ../../overlays/temporary {
              inherit (flake) inputs;
              pkgs = final;
            }).apply
              "handy-darwin-signature"
              prev.handy;
        }
      )
    ];
  };
  home = flake.inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ../../modules/home/desktop/dictation.nix
      {
        home.username = username;
        home.homeDirectory = homeDirectory;
        home.stateVersion = "25.11";
        xdg.enable = true;
        programs.voiceDictation.enable = true;
        wayland.windowManager.hyprland.package = null;
      }
    ];
  };
in
{
  inherit (home.config.programs.voiceDictation) prepare package;
  settings = home.config;
  files = home.config.home-files;
  linuxConfig = pkgs.runCommand "dictation-linux-config" {
    source = home.config.xdg.configFile."voxtype/config.toml".source;
  } ''cp "$source" "$out"'';
  service =
    if pkgs.stdenv.hostPlatform.isLinux then
      pkgs.runCommand "dictation-service" {
        source = home.config.xdg.configFile."systemd/user/voxtype.service".source;
      } ''cp "$source" "$out"''
    else
      pkgs.writeText "handy-launchd.json" (builtins.toJSON home.config.launchd.agents.handy.config);
}
