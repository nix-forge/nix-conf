{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  literalPath = "/tmp/tester's wallpapers%literal$dollar";
  homeFor =
    wallpaper:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs.extend (import ../../overlays { inherit inputs; });
      extraSpecialArgs = { inherit myLib; };
      modules = [
        ../../modules/home/desktop/wallpaper.nix
        ../../modules/home/desktop/capture.nix
        ../../modules/home/desktop/clipboard.nix
        {
          home = {
            username = "tester";
            homeDirectory = "/tmp/tester's home";
            stateVersion = "26.05";
          };
          xdg.userDirs.enable = true;
          desktop = {
            wallpaper = {
              enable = true;
              directory = literalPath;
            }
            // wallpaper;
            capture.enable = true;
            clipboard.enable = true;
          };
        }
      ];
    };
  rotating = homeFor {
    mode = "rotate";
    sources = {
      nasaSvs.enable = true;
      nasaImageLibrary.enable = true;
      clevelandMuseum.enable = true;
      wikimediaCommons.enable = true;
      smithsonian.enable = true;
    };
  };
  video = homeFor {
    mode = "video";
    video.path = literalPath;
  };
  orderingHome = homeFor {
    mode = "rotate";
    directory = "/tmp/wallpapers";
  };
  commands = builtins.filter (p: lib.hasPrefix "desktop-" p.name) rotating.config.home.packages;
  commandTree = pkgs.linkFarm "rendered-desktop-commands" (
    map (p: {
      inherit (p) name;
      path = p;
    }) commands
  );
  importer = lib.findFirst (
    p: p.name == "desktop-wallpaper-add"
  ) (throw "missing wallpaper importer") commands;
  execStart = builtins.head (
    lib.toList video.config.systemd.user.services.mpvpaper.Service.ExecStart
  );
  policyModule = (import ../../modules/shared/chromium-policies.nix).nixos;
  policies =
    definitions:
    lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        policyModule
        {
          options = {
            appearance.theme = lib.mkOption {
              type = lib.types.str;
              default = "none";
            };
            environment.etc = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
            system.activationScripts = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
          };
        }
      ]
      ++ definitions;
    };
  merged = policies [
    {
      programs.chromiumPolicies.policies = {
        nested.one = true;
        list = [ 1 ];
        nullable = null;
      };
    }
    {
      programs.chromiumPolicies.policies = {
        nested.two = "second";
        list = [ 2 ];
      };
    }
  ];
  value = merged.config.programs.chromiumPolicies.policies;
  invalid = policies [ { programs.chromiumPolicies.policies.bad = x: x; } ];
  scalar = policies [ { programs.chromiumPolicies.policies = true; } ];
  configHome = "/tmp/tester's \"quoted\" config\\%n\${HOME}";
  networkCommand = "!printf '%s\\n' \"network settings\"";
  iconTheme = "theme with \"quotes\" and \\slashes";
  recorder =
    name:
    pkgs.writeShellScriptBin name ''
      exec ${lib.getExe pkgs.python3} -c 'import json, sys; json.dump(sys.argv[1:], open("/run/${name}.json", "w"))' "$@"
    '';
  serviceHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit myLib;
      self = { };
      system = pkgs.stdenv.hostPlatform.system;
    };
    modules = [
      ../../modules/home/actual.nix
      ../../modules/home/desktop/bar.nix
      ../../modules/home/libreoffice.nix
      {
        options.stylix = lib.mkOption { type = lib.types.raw; };
        config = {
          nixpkgs.overlays = [
            (_: _: {
              ironbar = recorder "ironbar";
              languagetool = recorder "languagetool-http-server";
            })
          ];
          home = {
            username = "tester";
            homeDirectory = "/tmp/tester";
            stateVersion = "26.05";
          };
          xdg.configHome = configHome;
          xdg.configFile."ironbar/style.css".text = "* { color: black; }";
          services.actual = {
            enable = true;
            package = recorder "actual-server";
            dataDir = "/tmp/tester/actual";
          };
          desktop.bar = {
            enable = true;
            inherit networkCommand iconTheme;
          };
          programs.libreoffice = {
            enable = true;
            package = pkgs.emptyDirectory;
            languageTool = {
              cacheSize = 42;
              cacheTTLSeconds = 7;
              maxCheckThreads = 3;
              maxWorkQueueSize = 9;
            };
          };
          stylix = {
            icons.dark = iconTheme;
            fonts.sansSerif.name = "sans-serif";
          };
          lib.stylix.colors.withHashtag = lib.genAttrs [
            "base00"
            "base01"
            "base02"
            "base03"
            "base04"
            "base05"
            "base08"
            "base09"
            "base0A"
            "base0B"
            "base0D"
          ] (_: "#000000");
        };
      }
    ];
  };
  profilePatcher = lib.findFirst (
    p: p.name == "libreoffice-apply-settings"
  ) (throw "missing LibreOffice profile patcher") serviceHome.config.home.packages;
  preferenceDefinitions = value: {
    macos.preferences = lib.genAttrs [ "customUserPreferences" "customSystemPreferences" ] (_: {
      "org.example.preferences" = value;
    });
  };
  preferencesFor =
    definitions:
    (inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ../../modules/darwin/macos.nix
        {
          system.primaryUser = "tester";
          system.stateVersion = 6;
          macos.preferences.enable = true;
        }
      ]
      ++ map preferenceDefinitions definitions;
    }).config.system.defaults;
  darwinPreferences = preferencesFor [
    {
      first = true;
      nested.left = 1;
    }
    {
      second = false;
      nested.right = "two";
    }
  ];
  browserHomeFor =
    definitions:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs.extend (import ../../overlays { inherit inputs; });
      extraSpecialArgs = {
        inherit inputs myLib;
        osConfig = null;
      };
      modules = [
        ../../modules/home/browsers/firefox
        ../../modules/home/browsers/zen
        {
          options.appearance.theme = lib.mkOption {
            type = lib.types.str;
            default = "none";
          };
          config.home = {
            username = "tester";
            homeDirectory = "/tmp/tester";
            stateVersion = "26.05";
          };
        }
      ]
      ++ definitions;
    };
  browserHome = browserHomeFor [
    {
      programs.browserSuite = {
        geckoPolicies = {
          Preferences."example.first" = true;
          WebsiteFilter.Block = lib.mkBefore [ "https://first.invalid/*" ];
          DNSOverHTTPS.Enabled = true;
          ExtensionSettings.unmanaged.installation_mode = "allowed";
        };
        systemResolverPolicy.DNSOverHTTPS = {
          Enabled = false;
          ExcludedDomains = lib.mkBefore [ "first.invalid" ];
        };
      };
    }
    {
      programs.browserSuite = {
        geckoPolicies = {
          Preferences."example.second" = false;
          WebsiteFilter.Block = lib.mkAfter [ "https://second.invalid/*" ];
        };
        systemResolverPolicy.DNSOverHTTPS = {
          Locked = true;
          ExcludedDomains = lib.mkAfter [ "second.invalid" ];
        };
      };
    }
  ];
  invalidBrowserPolicies =
    definitions:
    !(builtins.tryEval (
      builtins.deepSeq (browserHomeFor definitions).config.programs.browserSuite.geckoPolicies true
    )).success;
in
{
  wallpaper-service-ordering =
    pkgs.runCommand "wallpaper-service-ordering" { nativeBuildInputs = [ pkgs.systemd ]; }
      ''
        mkdir -p units/graphical-session.target.wants runtime
        ${lib.concatMapStringsSep "\n"
          (name: ''
            cp ${orderingHome.config.xdg.configFile."systemd/user/${name}.service".source} units/${name}.service
                ln -s ../${name}.service units/graphical-session.target.wants/${name}.service
          '')
          [
            "awww"
            "desktop-wallpaper-directories"
            "desktop-wallpaper-rotate"
          ]
        }
        export XDG_RUNTIME_DIR="$PWD/runtime"
        export SYSTEMD_UNIT_PATH="$PWD/units:${pkgs.systemd}/example/systemd/user"
        systemd-analyze --user --man=no verify graphical-session.target > verification.log 2>&1 || {
          cat verification.log
          exit 1
        }
        if grep -E 'ordering cycle|deleted to break' verification.log; then
          exit 1
        fi
        touch "$out"
      '';
  gecko-policy-merge =
    assert lib.all
      (
        browser:
        let
          policies = browserHome.config.programs.${browser}.policies;
        in
        policies.Preferences == {
          "example.first" = true;
          "example.second" = false;
        }
        &&
          policies.WebsiteFilter.Block == [
            "https://first.invalid/*"
            "https://second.invalid/*"
          ]
        # Keep the adapters' deliberate top-level policy ownership.
        && policies.DNSOverHTTPS == { Enabled = true; }
        && !(policies.ExtensionSettings ? unmanaged)
        && policies.ExtensionSettings."*".installation_mode == "blocked"
      )
      [
        "firefox"
        "zen-browser"
      ];
    assert
      browserHome.config.programs.browserSuite.systemResolverPolicy.DNSOverHTTPS == {
        Enabled = false;
        Locked = true;
        ExcludedDomains = [
          "first.invalid"
          "second.invalid"
        ];
      };
    assert invalidBrowserPolicies [ { programs.browserSuite.geckoPolicies = true; } ];
    assert invalidBrowserPolicies [ { programs.browserSuite.geckoPolicies.invalid = x: x; } ];
    assert invalidBrowserPolicies [
      { programs.browserSuite.geckoPolicies.DisableTelemetry = true; }
      { programs.browserSuite.geckoPolicies.DisableTelemetry = false; }
    ];
    pkgs.writeText "gecko-merged-policy.json" (
      builtins.toJSON browserHome.config.programs.firefox.policies
    );
  macos-preference-merge =
    assert
      !(builtins.tryEval (
        builtins.deepSeq
          (preferencesFor [
            { first = true; }
            { first = false; }
          ]).CustomUserPreferences
          true
      )).success;
    assert
      !(builtins.tryEval (
        builtins.deepSeq (preferencesFor [ { invalid = x: x; } ]).CustomSystemPreferences true
      )).success;
    assert lib.all
      (
        name:
        darwinPreferences.${name}."org.example.preferences" == {
          first = true;
          second = false;
          nested = {
            left = 1;
            right = "two";
          };
        }
      )
      [
        "CustomUserPreferences"
        "CustomSystemPreferences"
      ];
    pkgs.runCommand "macos-preference-merge" { } "touch $out";
  ironbar-config =
    pkgs.runCommand "ironbar-config-literals"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        expectedCommand = networkCommand;
        expectedTheme = iconTheme;
      }
      ''
        python3 - ${serviceHome.config.xdg.configFile."ironbar/config.toml".source} <<'PY'
        import os
        import sys
        import tomllib

        with open(sys.argv[1], "rb") as source:
            config = tomllib.load(source)
        assert config["icon_theme"] == os.environ["expectedTheme"]
        network = next(item for item in config["end"] if item.get("name") == "network")
        assert network["bar"][0]["on_click"] == os.environ["expectedCommand"]
        assert config["center"][0]["type"] == "clock"
        assert len(config["end"]) == 7
        PY
        touch "$out"
      '';
  libreoffice-profile-path =
    pkgs.runCommand "libreoffice-profile-path"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        profilePath = "${configHome}/libreoffice/4/user/registrymodifications.xcu";
        languageToolExec =
          serviceHome.config.systemd.user.services.libreoffice-languagetool.Service.ExecStart;
      }
      ''
        ${profilePatcher}/bin/libreoffice-apply-settings
        python3 - <<'PY'
        import os
        import shlex
        import xml.etree.ElementTree as ET
        from pathlib import Path

        root = ET.parse(os.environ["profilePath"]).getroot()
        settings = {prop.get("{http://openoffice.org/2001/registry}name"): prop.findtext("value")
                    for item in root.findall("item") for prop in item.findall("prop")}
        assert settings["UseSkia"] == "true"
        assert settings["ForceSkia"] == "false"
        command = shlex.split(os.environ["languageToolExec"])
        properties = Path(command[command.index("--config") + 1]).read_text()
        values = dict(tuple(part.strip() for part in line.split("=", 1))
                      for line in properties.splitlines()
                      if line and not line.startswith("#"))
        assert values == {"cacheSize": "42", "cacheTTLSeconds": "7",
                          "maxCheckThreads": "3", "maxWorkQueueSize": "9"}, values
        PY
        touch "$out"
      '';
  service-command-arguments = pkgs.testers.runNixOSTest {
    name = "home-service-command-arguments";
    # QEMU can test argument handling through software emulation when KVM
    # is unavailable, while retaining acceleration on capable builders.
    requiredFeatures.kvm = false;
    nodes.machine = {
      system.stateVersion = "26.05";
      environment.etc."expected-arguments.json".text = builtins.toJSON {
        actual-server = [
          "--config"
          "${configHome}/actual/config.json"
        ];
        ironbar = [
          "--config"
          "${configHome}/ironbar/config.toml"
          "--theme"
          "${configHome}/ironbar/style.css"
        ];
      };
      systemd.services = lib.genAttrs [ "actual" "ironbar" ] (name: {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = serviceHome.config.systemd.user.services.${name}.Service.ExecStart;
        };
      });
    };
    testScript = ''
      import json

      machine.start()
      machine.wait_for_unit("multi-user.target")
      expected = json.loads(machine.succeed("cat /etc/expected-arguments.json"))
      for name, arguments in expected.items():
          received = json.loads(machine.succeed(f"cat /run/{name}.json"))
          assert received == arguments, (name, received, arguments)
    '';
  };
  policy-json =
    assert
      value.nested == {
        one = true;
        two = "second";
      };
    assert
      lib.sort builtins.lessThan value.list == [
        1
        2
      ];
    assert value.nullable == null;
    assert
      !(builtins.tryEval (builtins.deepSeq invalid.config.programs.chromiumPolicies.policies true))
      .success;
    assert
      !(builtins.tryEval (builtins.deepSeq scalar.config.programs.chromiumPolicies.policies true))
      .success;
    pkgs.runCommand "chromium-policy-json" { } ''
      test -n ${
        lib.escapeShellArg merged.config.environment.etc."helium/policies/managed/helium-system.json".text
      }
      touch "$out"
    '';
  desktop-commands =
    assert lib.hasInfix "%%literal$$dollar" execStart;
    pkgs.runCommand "desktop-command-regressions" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
      test -d ${commandTree}
      printf '%s' 'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==' | base64 -d > "source image.gif"
      PATH=/nonexistent ${lib.getExe importer} "$PWD/source image.gif"
      cmp "source image.gif" ${lib.escapeShellArg "${literalPath}/source image.gif"}
      test "$(stat -c %a ${lib.escapeShellArg literalPath})" = 700
      test "$(stat -c %a ${lib.escapeShellArg "${literalPath}/source image.gif"})" = 600
      status=0
      PATH=/nonexistent ${lib.getExe importer} || status=$?
      test "$status" = 64
      touch "$out"
    '';
}
