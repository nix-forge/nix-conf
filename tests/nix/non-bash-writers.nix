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
  crx =
    pkgs.writers.writePython3Bin "helium-crx-to-zip" { }
      ../../modules/home/helium-browser/scripts/crx-to-zip.py;
  preferences = pkgs.writers.writePython3Bin "helium-preference-defaults" {
    # Match the project formatter: long lines and leading binary operators.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../modules/home/helium-browser/scripts/preference-defaults.py;
  resolver = pkgs.writers.writePython3Bin "dev-vm-resolve-host" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../../homes/macbook-pro-m4/local/dev_vm_host.py;
  identity = pkgs.writers.writePython3Bin "write-jujutsu-identity" {
    flakeIgnore = [ "E501" ];
  } ../../modules/home/dev/scripts/write-jujutsu-identity.py;
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
  nuImport = pkgs.writeText "fixture-module.nu" ''
    export const fixture = "imported"
    export-env { error make {msg: "must not execute imported code"} }
  '';
  nuParseOnly = checkNu {
    name = "parse-only.nu";
    src = pkgs.replaceVarsWith {
      name = "rendered-nu.nu";
      src = pkgs.writeText "template.nu.in" ''
        use @module@ *
        error make {msg: "must not execute configuration"}
      '';
      replacements.module = nuImport;
    };
  };
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
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
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        ${lib.getExe resolver} --help > /dev/null
        ${lib.getExe identity} --help > /dev/null
        CRX_PROGRAM=${lib.getExe crx} PREFERENCES_PROGRAM=${lib.getExe preferences} \
          python3 ${./check-python-helpers.py}
        touch "$out"
      '';
  lua-plugin-validation = pkgs.runCommand "lua-plugin-validation" { } ''
    cmp ${plugin} ${../../modules/home/mpv/mpv-anime-toggle.lua}
    test ! -x ${plugin}
    test -f ${luaParseOnly}
    ${lua.interpreter} ${../lua/check-mpv-anime-toggle.lua} ${plugin}
    touch "$out"
  '';
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
      src = pkgs.writeText "import-source.nu" ''
        use ${pkgs.writeText "broken-module.nu" "export def broken ["} *
      '';
    };
    expectedBuilderLogEntries = [ "Failed to parse content" ];
  };
  nushell-generated-config =
    pkgs.runCommand "nushell-generated-config" { checkedFiles = home.config.home.extraDependencies; }
      ''
        test -f ${nuParseOnly}
        export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
        mkdir -p "$HOME" "$XDG_CONFIG_HOME"
        ${lib.getExe pkgs.nushell} --no-config-file --commands '
          use std/assert
          source ${envFile}
          source ${configFile}
          assert equal $env.LITERAL "quote\" slash\\ newline\n dollar$literal"
          assert equal $env.PREPEND "tail"
          assert equal $env.APPEND "head"
          assert ("/tmp/path with spaces" in $env.PATH)
          assert ("/tmp/quote\"and$sign" in $env.PATH)
        '
        PREPEND=prior APPEND=after ${lib.getExe pkgs.nushell} --no-config-file --commands '
          use std/assert
          source ${envFile}
          assert equal $env.PREPEND "prior:tail"
          assert equal $env.APPEND "head:after"
        '
        touch "$out"
      '';
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
