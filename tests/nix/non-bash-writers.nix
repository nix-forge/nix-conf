{
  pkgs,
  myLib,
  inputs,
}:
let
  inherit (pkgs) lib;
  checkLua = myLib.writers.checkLuaFile { inherit pkgs; };
  checkNu = myLib.writers.checkNuFile { inherit pkgs; };
  lua = pkgs.mpv.unwrapped.lua;
  crx = pkgs.writers.writePython3Bin "helium-crx-to-zip" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../modules/home/browsers/helium/scripts/crx_to_zip.py;
  preferences = pkgs.writers.writePython3Bin "helium-preference-defaults" {
    # Match the project formatter: long lines and leading binary operators.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../modules/home/browsers/helium/scripts/preference_defaults.py;
  identity = pkgs.writers.writePython3Bin "write-jujutsu-identity" {
    libraries = [ (myLib.python.notificationProcess { inherit pkgs; }) ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../modules/home/dev/scripts/write_jujutsu_identity.py;
  plugin = checkLua {
    name = "mpv-anime-toggle.lua";
    src = ../../modules/home/mpv/mpv-anime-toggle.lua;
    inherit lua;
    readGlobals = [ "mp" ];
  };
  luaParseOnly = checkLua {
    name = "parse-only.lua";
    src = pkgs.writeText "parse-only-source.lua" "error('validation must not execute this')";
    inherit lua;
  };
  nuImport = pkgs.writeText "fixture-module.nu" (builtins.readFile ./scripts/fixture-module.nu);
  nuParseOnly = checkNu {
    name = "parse-only.nu";
    src = pkgs.replaceVarsWith {
      name = "rendered-nu.nu";
      src = pkgs.writeText "template.nu.in" (builtins.readFile ./scripts/nushell-parse-only-config.nu.in);
      replacements.module = nuImport;
    };
  };
  home = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = pkgs.extend (import ../../overlays { inherit inputs; });
    extraSpecialArgs = { inherit myLib; };
    modules = [
      ../../modules/home/shells/nushell
      {
        home = {
          username = "tester";
          homeDirectory = "/home/tester";
          stateVersion = "26.05";
          sessionPath = [
            "/tmp/path with spaces"
            "/tmp/quote\"and$sign"
          ];
          sessionVariables = {
            LITERAL = "quote\" slash\\ newline\n dollar$literal";
            PREPEND = "$PREPEND\${PREPEND:+:}tail";
            APPEND = "head\${APPEND:+:$APPEND}";
          };
        };
        programs.nushell.enable = true;
      }
    ];
  };
  configFile = home.config.home.file."${home.config.programs.nushell.configDir}/config.nu".source;
  envFile = home.config.home.file."${home.config.programs.nushell.configDir}/env.nu".source;
in
{
  non-bash-python-helpers =
    pkgs.runCommand "non-bash-python-helpers" { nativeBuildInputs = [ pkgs.python3 ]; }
      (
        (import ../../lib/templates/text.nix) ./scripts/non-bash-python-helpers.sh {
          lib_getExe_identity = lib.getExe identity;
          lib_getExe_crx = lib.getExe crx;
          lib_getExe_preferences = lib.getExe preferences;
          check_python_helpers_py = ./check_python_helpers.py;
        }
      );
  lua-plugin-validation = pkgs.runCommand "lua-plugin-validation" { } (
    (import ./../../lib/templates/text.nix) ./scripts/check-mpv-lua-writer.sh {
      inherit plugin;
      modules_home_mpv_mpv_anime_toggle_lua = ../../modules/home/mpv/mpv-anime-toggle.lua;
      inherit luaParseOnly;
      lua_interpreter = lua.interpreter;
      lua_check_mpv_anime_toggle_lua = ../lua/check-mpv-anime-toggle.lua;
    }
  );
  lua-invalid-syntax = pkgs.testers.testBuildFailure' {
    drv = checkLua {
      name = "invalid.lua";
      src = pkgs.writeText "invalid-source.lua" "local function broken(";
      inherit lua;
    };
  };
  lua-invalid-global = pkgs.testers.testBuildFailure' {
    drv = checkLua {
      name = "invalid-global.lua";
      src = pkgs.writeText "invalid-global-source.lua" "typo.commandv('test')";
      inherit lua;
      readGlobals = [ "mp" ];
    };
    expectedBuilderExitCode = 1;
    expectedBuilderLogEntries = [ "accessing undefined variable" ];
  };
  lua-readonly-host-api = pkgs.testers.testBuildFailure' {
    drv = checkLua {
      name = "overwritten-host-api.lua";
      src = pkgs.writeText "overwritten-host-api-source.lua" "mp.commandv = function() end";
      inherit lua;
      readGlobals = [ "mp" ];
    };
    expectedBuilderLogEntries = [ "setting read-only field" ];
  };
  nushell-invalid-import = pkgs.testers.testBuildFailure' {
    drv = checkNu {
      name = "invalid-import.nu";
      src = pkgs.writeText "import-source.nu" (
        (import ../../lib/templates/text.nix) ./scripts/nushell-broken-import-config.nu.in {
          pkgs_writeText_broken_module_nu_export_def_broken = pkgs.writeText "broken-module.nu" "export def broken [";
        }
      );
    };
    expectedBuilderLogEntries = [ "Failed to parse content" ];
  };
  nushell-generated-config =
    pkgs.runCommand "nushell-generated-config" { checkedFiles = home.config.home.extraDependencies; }
      (
        (import ../../lib/templates/text.nix) ./scripts/nushell-generated-config.sh {
          inherit nuParseOnly;
          lib_getExe_pkgs_nushell = lib.getExe pkgs.nushell;
          inherit envFile;
          inherit configFile;
        }
      );
  nushell-invalid-syntax = pkgs.testers.testBuildFailure' {
    drv = checkNu {
      name = "invalid.nu";
      src = pkgs.replaceVarsWith {
        name = "invalid-rendered.nu";
        src = pkgs.writeText "invalid-template.nu.in" "@body@";
        replacements.body = "def broken [";
      };
    };
  };
}
