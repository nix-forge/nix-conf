{
  inputs,
  lib,
  myLib,
  ...
}:
let
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
  mkHome =
    system: extraModules: extraSpecialArgs:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = {
        inherit myLib;
      }
      // extraSpecialArgs;
      modules = [
        (import ../../modules/shared/nix-settings.nix).homeManager
        ../../modules/home/actual.nix
        ../../modules/home/dev/containers.nix
        ../../modules/home/dev/git.nix
        ../../modules/home/shells/nushell/settings.nix
        ({ pkgs, ... }: {
          home = {
            username = "platform-check";
            homeDirectory =
              if pkgs.stdenv.hostPlatform.isDarwin then "/Users/platform-check" else "/home/platform-check";
            uid = 1000;
            stateVersion = "25.05";
          };
          services.actual = {
            enable = true;
            package = pkgs.writeShellScriptBin "actual-server" "exit 0";
            dataDir = "/tmp/actual-platform-check";
          };
        })
      ]
      ++ extraModules;
    };
  checkSystem =
    system:
    let
      home = (mkHome system [ ] { }).config;
      linux = lib.hasSuffix "-linux" system;
      rootless = (mkHome system [ { programs.docker-cli.rootless.enable = true; } ] { }).config;
      integrated = (mkHome system [ ] { osConfig.virtualisation.docker.rootless.enable = linux; }).config;
      disabled = (mkHome system [ { services.actual.enable = lib.mkForce false; } ] { }).config;
      packageNames = map lib.getName home.home.packages;
    in
    assert lib.all (a: a.assertion) home.assertions;
    assert home.nix.settings.sandbox == true;
    assert home.nix.settings.sandbox-fallback == false;
    assert (home.systemd.user.services ? actual) == linux;
    assert (home.launchd.agents ? actual) == !linux;
    assert !(disabled.systemd.user.services ? actual);
    assert !(disabled.launchd.agents ? actual);
    assert lib.hasInfix "run " home.home.activation.actualSetup.data;
    assert !home.programs.docker-cli.rootless.enable;
    assert !(home.programs.docker-cli.contexts ? rootless);
    assert !(home.programs.docker-cli.settings ? currentContext);
    assert lib.elem "docker-up" packageNames == !linux;
    assert integrated.programs.docker-cli.rootless.enable == linux;
    assert (
      if linux then
        lib.all (a: a.assertion) rootless.assertions
        &&
          rootless.programs.docker-cli.contexts.rootless.Endpoints.docker.Host
          == "unix:///run/user/1000/docker.sock"
        && rootless.programs.docker-cli.settings.currentContext == "rootless"
      else
        !(builtins.tryEval rootless.home.activationPackage.drvPath).success
    );
    assert lib.hasInfix "delete_previous_word" home.programs.nushell.extraConfig;
    assert lib.hasInfix "delete_to_line_start" home.programs.nushell.extraConfig;
    assert lib.elem ".DS_Store" home.programs.git.ignores;
    assert (home.programs.git.settings.core.fsmonitor or false) == !linux;
    true;
  checkPackages =
    system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # Exercise the same platform-filtered public set supplied to real homes.
      # The raw registry intentionally exposes unsupported packages for metadata.
      packages = inputs.nixpkgs-personal.packages.${system};
      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit system;
          self.packages.${system} = packages;
        };
        modules = [
          ../../modules/home/cli/remindctl.nix
          ../../modules/home/microsoft-teams.nix
          (import ../../modules/shared/fonts).homeManager
          {
            fonts.fontconfig.enable = lib.mkForce false;
            home = {
              username = "package-check";
              homeDirectory = "/tmp/package-check";
              stateVersion = "25.05";
            };
          }
        ];
      };
    in
    assert lib.all (lib.meta.availableOn pkgs.stdenv.hostPlatform) (builtins.attrValues packages);
    assert lib.all (lib.meta.availableOn pkgs.stdenv.hostPlatform) home.config.home.packages;
    assert lib.elem pkgs.noto-fonts home.config.home.packages;
    true;
in
{
  perSystem = { pkgs, ... }: {
    checks.platform-contracts =
      assert lib.all checkSystem systems;
      assert lib.all checkPackages systems;
      assert inputs.self.nixosConfigurations.desktop.config.nix.settings.sandbox == true;
      assert inputs.self.nixosConfigurations.desktop.config.homelab.profiles.desktop.enable;
      assert !inputs.self.nixosConfigurations.desktop.config.homelab.profiles.media.enable;
      assert builtins.hasAttr "homelab-background"
        inputs.self.nixosConfigurations.desktop.config.systemd.slices;
      assert
        inputs.self.darwinConfigurations.macbook-pro-m4.config.determinateNix.customSettings.sandbox
        == true;
      let
        desktop = inputs.self.nixosConfigurations.desktop.config.home-manager.users.ianmh;
        macbook = inputs.self.darwinConfigurations.macbook-pro-m4.config.home-manager.users.ianmh;
      in
      assert desktop.home.activation ? configureCodexDesktopAppearance;
      assert macbook.home.activation ? configureCodexDesktopAppearance;
      assert desktop.programs.docker-cli.rootless.enable;
      assert !macbook.programs.docker-cli.rootless.enable;
      assert desktop.programs.mpv.config.target-colorspace-hint-mode == "source";
      assert !(macbook.programs.mpv.config ? target-colorspace-hint-mode);
      pkgs.runCommand "platform-contracts" { } "touch $out";
  };
}
