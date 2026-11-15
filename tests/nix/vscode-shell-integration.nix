{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  editor = pkgs.writeShellApplication {
    name = "fixture-editor";
    text = builtins.readFile ./scripts/vscode-fixture-editor.sh;
  };
  direnv = pkgs.writeShellApplication {
    name = "fixture-direnv";
    text = builtins.readFile ./scripts/vscode-fixture-direnv.sh;
  };
  home =
    package: enableDirenv: enableEditor:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ../../modules/home/vscode/settings.nix
        {
          home = {
            username = "tester";
            homeDirectory = "/tmp/vscode-shell-fixture";
            stateVersion = "26.05";
          };
          programs.bash.enable = true;
          programs.vscode = {
            enable = enableEditor;
            inherit package;
            profiles.default = {
              extensions = lib.mkForce [ ];
              userSettings = lib.mkForce { };
            };
          };
          programs.direnv = {
            enable = enableDirenv;
            package = direnv;
            enableBashIntegration = false;
          };
        }
      ];
    };
  hook =
    name: package: enableDirenv: enableEditor:
    pkgs.writeText name (home package enableDirenv enableEditor).config.programs.bash.initExtra;
in
assert
  !(builtins.hasAttr (builtins.unsafeDiscardStringContext editor.drvPath) (
    builtins.getContext (home editor false false).config.programs.bash.initExtra
  ));
pkgs.runCommand "vscode-shell-integration"
  {
    nativeBuildInputs = [ pkgs.bash ];
    nullHook = hook "vscode-null-hook.sh" null false true;
    selectedHook = hook "vscode-selected-hook.sh" editor true true;
    optionalHook = hook "vscode-optional-hook.sh" editor false true;
    disabledHook = hook "vscode-disabled-hook.sh" editor false false;
    fixture = ./scripts/check-vscode-shell-integration.sh;
  }
  ''
    bash "$fixture"
    mkdir -p "$out"
  ''
