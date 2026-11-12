{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  # Exercise the public selector seam without tying expectations to catalog data.
  selector =
    package: versionOverride:
    let
      evaluated = lib.evalModules {
        specialArgs = {
          inherit pkgs;
          inputs.nix4vscode.overlays.default = _: _: {
            nix4vscode.forVscodeVersion = version: ids: { inherit version ids; };
          };
        };
        modules = [
          ../../modules/home/vscode/catalog.nix
          {
            options = {
              programs.vscode.enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
              };
              programs.vscode.package = lib.mkOption { type = lib.types.nullOr lib.types.package; };
              lib = lib.mkOption {
                type = lib.types.attrsOf lib.types.attrs;
                default = { };
              };
              assertions = lib.mkOption {
                type = lib.types.listOf lib.types.attrs;
                default = [ ];
              };
            };
            config.programs.vscode = {
              inherit package;
            }
            // lib.optionalAttrs (versionOverride != null) { extensionCompatibilityVersion = versionOverride; };
          }
        ];
      };
    in
    evaluated.config.lib.vscode.catalogExtensions [ "fixture.client" ];
  languageNames = [
    "bash"
    "cpp"
    "docker"
    "go"
    "java"
    "javascript"
    "lua"
    "matlab"
    "notebooks"
    "nix"
    "nushell"
    "python"
    "rust"
    "solidity"
    "typescript"
    "typst"
    "web"
  ];
  mkHome =
    system: modules: extra:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = { inherit inputs; };
      modules = modules ++ [
        {
          home = {
            username = "editor-test";
            homeDirectory =
              if lib.hasSuffix "-darwin" system then "/Users/editor-test" else "/home/editor-test";
            stateVersion = "26.05";
          };
        }
        extra
      ];
    };
  oldNotebookEditor =
    (mkHome "x86_64-linux" [ ../../modules/home/vscode/languages/notebooks.nix ] {
      programs.vscode.extensionCompatibilityVersion = "1.104.0";
    }).config;
  languageModule = name: ../../modules/home/vscode/languages + "/${name}.nix";
  checkSystem =
    system:
    let
      base = (mkHome system [ ../../modules/home/vscode/defaultvisual.nix ] { }).config;
      combined = (mkHome system (map languageModule languageNames) { }).config;
      settings = combined.programs.vscode.profiles.default.userSettings;
      # Force actual extension derivations, including catalog lookup failures,
      # without downloading the editor/toolchain closures just to test composition.
      extensions = map (
        extension: extension.drvPath
      ) combined.programs.vscode.profiles.default.extensions;
      standalone =
        name:
        let
          home = (mkHome system [ (languageModule name) ] { }).config;
        in
        home.programs.vscode.enable
        && !home.programs.direnv.enable
        && !home.programs.git.enable
        && lib.all (a: a.assertion) home.assertions
        && builtins.deepSeq (builtins.toJSON home.programs.vscode.profiles.default.userSettings) true
        && builtins.deepSeq (map (
          extension: extension.drvPath
        ) home.programs.vscode.profiles.default.extensions) true;
      withGit =
        signing:
        (mkHome system [ ../../modules/home/vscode/defaultvisual.nix ] {
          programs.git.enable = true;
          programs.git.signing.signByDefault = signing;
        }).config.programs.vscode.profiles.default.userSettings;
      withDirenvHome =
        (mkHome system [ (languageModule "python") ] { programs.direnv.enable = true; }).config;
      withDirenv = withDirenvHome.programs.vscode.profiles.default.userSettings;
    in
    assert lib.all standalone languageNames;
    assert lib.all (a: a.assertion) combined.assertions;
    assert !base.programs.direnv.enable && !base.programs.git.enable;
    assert settings."extensions.autoUpdate" == "off";
    assert
      (mkHome system [ ../../modules/home/vscode/default.nix ] {
        programs.vscode.extensionCompatibilityVersion = "1.120.0";
      }).config.programs.vscode.profiles.default.userSettings."extensions.autoUpdate" == false;
    assert builtins.deepSeq extensions true;
    assert builtins.deepSeq (builtins.toJSON settings) true;
    assert
      settings."[javascript]"."editor.defaultFormatter"
      == settings."[typescript]"."editor.defaultFormatter";
    assert settings."[shellscript]"."editor.defaultFormatter" == "mads-hartmann.bash-ide-vscode";
    assert settings."python.terminal.activateEnvironment";
    assert !withDirenv."python.terminal.activateEnvironment";
    assert builtins.deepSeq (map (
      extension: extension.drvPath
    ) withDirenvHome.programs.vscode.profiles.default.extensions) true;
    assert !(withGit false ? "git.enableCommitSigning");
    assert (withGit true)."git.enableCommitSigning";
    assert lib.all (
      binding: (binding.when or null) == null || !(lib.hasInfix "config.editor.autoSave" binding.when)
    ) combined.programs.vscode.profiles.default.keybindings;
    true;
in
assert
  (selector (pkgs.emptyDirectory // { version = "1.130.1"; }) null) == {
    version = "1.130.1";
    ids = [ "fixture.client" ];
  };
assert (selector (pkgs.emptyDirectory // { version = "1.130.1"; }) "1.120.0").version == "1.120.0";
assert (selector null null).version == pkgs.vscode.version;
assert (selector (pkgs.emptyDirectory // { version = null; }) null).version == pkgs.vscode.version;
assert !(builtins.tryEval oldNotebookEditor.programs.vscode.enable).success;
assert lib.all checkSystem [
  "x86_64-linux"
  "aarch64-darwin"
];
pkgs.runCommand "vscode-configuration" { } "touch $out"
