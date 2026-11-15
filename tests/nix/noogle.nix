{
  pkgs,
  inputs,
  myLib,
}:
let
  inherit (pkgs) lib;
  wallpaperConfigHome = "/tmp/tester's home/configured wallpaper %literal$dollar";
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
          xdg.userDirs.enable = false;
          xdg.configHome = wallpaperConfigHome;
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
    connections = {
      esaHubble.enable = true;
      esaWebb.enable = true;
      wikimediaCommons.enable = true;
    };
    categories = {
      cityscapes.enable = false;
      space = {
        connections.esaHubble = false;
        subcategories.nebulae.connections.esaHubble = true;
      };
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
  settings = lib.findFirst (
    p: p.name == "desktop-wallpaper-settings"
  ) (throw "missing wallpaper preferences command") commands;
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
    pkgs.writeShellScriptBin name (
      (import ../../lib/templates/text.nix) ./scripts/noogle-run.sh {
        lib_getExe_pkgs_python3 = lib.getExe pkgs.python3;
        inherit name;
        recorderSource = ./scripts/noogle_record_args.py;
      }
    );
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
      specialArgs = { inherit inputs; };
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
    assert
      orderingHome.config.systemd.user.services.desktop-wallpaper-directories.Service.RemainAfterExit;
    assert
      orderingHome.config.systemd.user.services.desktop-wallpaper-rotate.Unit.StartLimitIntervalSec == 0;
    pkgs.runCommand "wallpaper-service-ordering" { nativeBuildInputs = [ pkgs.systemd ]; } (
      (import ../../lib/templates/text.nix) ./scripts/wallpaper-service-ordering.sh {
        lib_concatMapStringsSep_n_name_cp_orderingHome_config_xdg_co =
          lib.concatMapStringsSep "\n"
            (
              name:
              ((import ../../lib/templates/text.nix) ./scripts/stage-wallpaper-ordering-unit.sh {
                orderingHome_config_xdg_configFile_systemd_user_name_service =
                  orderingHome.config.xdg.configFile."systemd/user/${name}.service".source;
                inherit name;
              })
            )
            [
              "awww"
              "desktop-wallpaper-directories"
              "desktop-wallpaper-rotate"
            ];
        pkgs_systemd = pkgs.systemd;
      }
    );
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
      (
        (import ../../lib/templates/text.nix) ./scripts/ironbar-config-literals.sh {
          scripts_check_ironbar_py = ./scripts/check_ironbar.py;
          serviceHome_config_xdg_configFile_ironbar_config_toml_source =
            serviceHome.config.xdg.configFile."ironbar/config.toml".source;
        }
      );
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
        python3 ${./scripts/check_libreoffice_profile.py}
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
    testScript = builtins.readFile ./scripts/noogle_test.py;
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
    pkgs.runCommand "chromium-policy-json" { } (
      (import ../../lib/templates/text.nix) ./scripts/chromium-policy-json.sh {
        lib_escapeShellArg_merged_config_environment_etc_helium_poli =
          lib.escapeShellArg
            merged.config.environment.etc."helium/policies/managed/helium-system.json".text;
      }
    );
  desktop-commands =
    assert
      !(builtins.tryEval
        (homeFor {
          mode = "rotate";
          directory = "relative-wallpapers";
        }).activationPackage.drvPath
      ).success;
    assert rotating.config.desktop.capture.directory == "/tmp/tester's home/Pictures/Screenshots";
    assert lib.all (entry: entry.assertion) rotating.config.assertions;
    assert lib.hasInfix "%%literal$$dollar" execStart;
    pkgs.runCommand "desktop-command-regressions"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
      }
      (
        (import ../../lib/templates/text.nix) ./scripts/desktop-command-regressions.sh {
          inherit commandTree;
          lib_getExe_importer = lib.getExe importer;
          lib_escapeShellArg_literalPath_source_image_gif = lib.escapeShellArg "${literalPath}/source image.gif";
          lib_escapeShellArg_literalPath = lib.escapeShellArg literalPath;
          configuredPolicyDirectory = lib.escapeShellArg "${wallpaperConfigHome}/desktop-wallpaper";
          rotating_config_xdg_configFile_desktop_wallpaper_policy_comm =
            rotating.config.xdg.configFile."desktop-wallpaper/policy-command".source;
          lib_getExe_settings = lib.getExe settings;
        }
      );
}
