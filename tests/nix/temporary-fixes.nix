{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  guard = import ../../overlays/temporary/guard.nix { inherit lib; };
  fixture = {
    name = "fixture";
    reason = "Regression in the fixture package";
    upstream = "https://example.invalid/fixture";
    removal = "The fixed release is packaged";
    reviewedRevision = "reviewed";
    affectedVersions = {
      from = "1.2";
      until = "1.4";
    };
  };
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  accepts = version: succeeds (guard fixture "reviewed" { inherit version; });
  fixes = import ../../overlays/temporary { inherit pkgs inputs; };
  nvidiaFixture =
    hooks: fixes.apply "nvidia-bin-patchelf" (pkgs.runCommand "nvidia-hook-fixture" hooks "touch $out");
  nvidiaNullHooks = nvidiaFixture {
    postInstall = null;
    postInstallCheck = null;
  };
  nvidiaExistingHooks = nvidiaFixture {
    postInstall = "echo existing-install-hook";
    postInstallCheck = "echo existing-check-hook";
  };

  changed = import ../../overlays/temporary {
    inherit pkgs;
    inputs = inputs // {
      nixpkgs = inputs.nixpkgs // {
        rev = "unreviewed";
      };
    };
  };
  moduleFixes = import ../../overlays/temporary { inherit lib inputs; };
  consentHomeReplacement = moduleFixes.apply "home-manager-app-management-consent" {
    upstream = inputs.home-manager;
    replacement = moduleFixes.apply "home-manager-protected-apps" inputs.home-manager;
  };
  protectedCopyReplacement = moduleFixes.apply "home-manager-protected-apps" inputs.home-manager;
  protectedCopySource = builtins.readFile (builtins.head protectedCopyReplacement.imports);
  consentMutant =
    source:
    moduleFixes.apply "home-manager-app-management-consent" {
      upstream = inputs.home-manager;
      replacement = protectedCopyReplacement // {
        imports = [ (builtins.toFile "mutant-copyapps.nix" source) ];
      };
    };
  changedDarwinModule = import ../../overlays/temporary {
    inherit lib;
    inputs = inputs // {
      nix-darwin = inputs.nix-darwin // {
        rev = "unreviewed";
      };
    };
  };
  changedHomeManager = import ../../overlays/temporary {
    inherit lib;
    inputs = inputs // {
      home-manager = inputs.home-manager // {
        rev = "unreviewed";
      };
    };
  };
  changedDeterminateModule = import ../../overlays/temporary {
    inherit lib;
    inputs = inputs // {
      determinate = inputs.determinate // {
        rev = "unreviewed";
      };
    };
  };
  changedDeterminate = import ../../overlays/temporary {
    inherit pkgs;
    inputs = inputs // {
      determinate = inputs.determinate // {
        inputs = inputs.determinate.inputs // {
          nix = inputs.determinate.inputs.nix // {
            rev = "unreviewed";
          };
        };
      };
    };
  };
  changedStylix = import ../../overlays/temporary {
    inherit pkgs;
    inputs = inputs // {
      stylix = inputs.stylix // {
        rev = "unreviewed";
      };
    };
  };
  # Exercise the selected upstream module after retiring its argument adapter.
  homeManagerPortal =
    portalPackage: finalPackage:
    (import (inputs.home-manager + "/modules/services/window-managers/hyprland/default.nix") {
      inherit lib pkgs;
      config.wayland.windowManager.hyprland = { inherit portalPackage finalPackage; };
    }).options.wayland.windowManager.hyprland.finalPortalPackage.default;
  portalFixture = lib.makeOverridable (
    {
      label ? "original",
    }:
    pkgs.runCommand "portal-${label}" { } "touch $out"
  ) { };
  compositorFixture = pkgs.runCommand "compositor" { } "touch $out";
  legacyCompositorFixture = pkgs.runCommand "legacy-compositor" { } "touch $out";
  legacyPortalFixture = lib.makeOverridable (
    {
      hyprland ? legacyCompositorFixture,
      label ? "original",
    }:
    pkgs.runCommand "portal-${label}-${hyprland.name}" { inherit hyprland; } "touch $out"
  ) { };
  changedAnywhere = import ../../overlays/temporary {
    inherit pkgs;
    inputs = inputs // {
      nixos-anywhere = inputs.nixos-anywhere // {
        rev = "unreviewed";
      };
    };
  };
  changedHyprland = import ../../overlays/temporary {
    inherit pkgs;
    inputs = inputs // {
      hyprland = inputs.hyprland // {
        rev = "unreviewed";
      };
    };
  };
  overlay = import ../../overlays { inherit inputs; };
  selected = pkgs.extend overlay;
  nixfTool = fixes.apply "nixf-flake-builtins" pkgs.nixf-diagnose;
  # Reconstruct the owning dependency scope independently of the selection overlay.
  determinateSource = inputs.determinate.inputs.nix;
  determinateSystem = pkgs.stdenv.hostPlatform.system;
  determinateOwningPkgs = import determinateSource.inputs.nixpkgs {
    localSystem = {
      system = determinateSystem;
    };
    overlays = [ determinateSource.overlays.internal ];
  };
  determinateOwningFixes = import ../../overlays/temporary {
    pkgs = determinateOwningPkgs;
    inherit inputs;
  };
  determinateRaw = determinateOwningPkgs.nixComponents2;
  determinateLibgit = determinateOwningFixes.apply "determinate-libgit2-trailing-slash" determinateOwningPkgs.nixDependencies2.libgit2;
  determinateScoped = determinateRaw.overrideScope (_: _: { libgit2 = determinateLibgit; });
  determinateExpected =
    if pkgs.stdenv.hostPlatform.isDarwin then
      fixes.apply "determinate-darwin-tests" determinateScoped.nix-everything
    else
      determinateScoped.nix-everything;
  determinateGateNames = [
    "nix-util-tests-run"
    "nix-store-tests-run"
    "nix-expr-tests-run"
    "nix-fetchers-tests-run"
    "nix-flake-tests-run"
    "nix-functional-tests"
  ]
  ++ lib.optional pkgs.stdenv.hostPlatform.isLinux "nix-util-tests-run-without-new-syscalls";
  determinateDependency =
    name: component:
    (lib.findSingle (p: (p.pname or "") == name) (throw "Missing Determinate dependency: ${name}")
      (throw "Duplicate Determinate dependency: ${name}")
      component.buildInputs
    ).out;

  nhAt =
    version:
    pkgs.nh-unwrapped.overrideAttrs {
      inherit version;
      __intentionallyOverridingVersion = true;
    };
  # The generated Haskell package keeps its exposed version outside
  # overrideAttrs, so merge the fixture version at the package boundary.
  nomAt = version: pkgs.nix-output-monitor // { inherit version; };
  nhFixed = nhAt "4.4.3";
  nhUpdated = import ../../overlays/temporary {
    pkgs = pkgs // {
      nh-unwrapped = nhFixed;
    };
    inputs = inputs // {
      nixpkgs = inputs.nixpkgs // {
        rev = "unreviewed";
      };
    };
  };
  # Exercise the consumer with Home Manager's standard module arguments.
  claudeHome = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = selected;
    modules = [
      ../../modules/home/dev/agentic-tui/claude.nix
      {
        home = {
          username = "module-check";
          homeDirectory = "/tmp/module-check";
          stateVersion = "25.11";
        };
      }
    ];
  };
  # Exercise the public selection interface and its module consumers.
  packages = {
    codex = [ selected.codex ];
    ghostty-bash = [
      (fixes.apply "ghostty-bash-prompt" (
        if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty
      )).shell_integration
    ];
    actual = [ selected.actual-server ];
    helium-darwin = map (system: inputs.helium-browser-darwin.packages.${system}.default) (
      builtins.filter (lib.hasSuffix "-darwin") (import ../../flake/supported-systems.nix)
    );
    navidrome = pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux selected.navidrome;
    audiomuseai-plugin = lib.optional pkgs.stdenv.hostPlatform.isLinux selected.navidrome-plugin-audiomuseai-personal;
    prism = (import ../../modules/home/prismlauncher.nix { pkgs = selected; }).home.packages;
    claude = [ claudeHome.config.programs.claude-code.package ];
    deploy = [ selected.deploy-rs ];
    determinate = [ selected.nix ];
    typescript-language-server = [ selected.typescript-language-server ];
    nh = [ selected.nh ];
    nom = [ selected.nix-output-monitor ];
    rclone = [ selected.rclone ];
    nu-scripts = [ selected.nu_scripts ];
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    nvidia = lib.optional (pkgs.stdenv.hostPlatform.system == "x86_64-linux") (
      fixes.apply "nvidia-bin-patchelf" pkgs.linuxPackages.nvidiaPackages.production
    );
    jellyfin-web = [ selected.jellyfin-web ];
    determinate-module = [ (import ./determinate-module.nix { inherit pkgs inputs; }) ];
    microsocks = [ selected.microsocks ];
    stirling-pdf = [ selected.stirling-pdf ];
    hyprshell = [ selected.hyprshell ];
    hypridle = [ selected.hypridle ];
    virt-manager = [ selected.virt-manager ];
    grimblast = [ selected.grimblast-region ];
    hyprland = [ selected.hyprland ];
    portal = [ selected.xdg-desktop-portal-hyprland ];
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    application-signatures = [
      selected.aerospace
      selected.signal-desktop
      selected.zoom-us
    ];
    swift = [ selected.swift ];
    swift-consumers = [
      selected.ocr-capture
      selected.finder-favorites
      selected.vorssaint
    ];
  };
  vendorGuiLayout = pkgs.runCommand "t3code-vendor-gui-layout-contract" {
    nativeBuildInputs = [
      pkgs.unzip
      pkgs.zip
    ];
    extractor = ../../overlays/temporary/scripts/t3code-vendor-gui.sh;
  } (builtins.readFile ./scripts/t3code-vendor-gui-layout.sh);
  derivations = lib.mapAttrs (_: map (p: p.drvPath)) (
    packages // { t3code-vendor-gui-layout = [ vendorGuiLayout ]; }
  );
in
assert lib.all (value: value) (
  builtins.attrValues (
    import ../../overlays/temporary/tests/t3code-vendor-gui-contract.nix {
      inherit lib guard;
      fix = import ../../overlays/temporary/t3code-darwin-vendor-gui.nix {
        inherit lib;
        pkgs = pkgs // {
          symlinkJoin = attrs: attrs;
          stdenvNoCC = {
            mkDerivation =
              attrs: attrs // { outPath = "/nix/store/88888888888888888888888888888888-vendor-app"; };
          };
          fetchurl =
            attrs: attrs // { outPath = "/nix/store/99999999999999999999999999999999-vendor-archive"; };
          runCommand =
            name: attrs: _command:
            attrs
            // {
              inherit name;
              outPath = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-vendor-gui-entry";
            };
        };
      };
    }
  )
);
assert selected.blocky.drvPath == (fixes.apply "blocky-multiple-dnskeys" pkgs.blocky).drvPath;
assert selected.blocky.doCheck;
assert lib.elem ../../overlays/temporary/patches/blocky-multiple-dnskeys.patch
  selected.blocky.patches;
assert
  !(succeeds
    (fixes.apply "blocky-multiple-dnskeys" (pkgs.blocky // { version = "0.35.1"; })).drvPath
  );
assert !(succeeds (changed.apply "blocky-multiple-dnskeys" pkgs.blocky).drvPath);
assert (import ./crashpad-lock-parameter.nix).defaultFalse;
assert import ../../overlays/temporary/tests/darwin-functional-contract.nix;
assert
  !pkgs.stdenv.hostPlatform.isDarwin
  || (
    selected.aerospace.dontStrip
    && selected.zoom-us.dontStrip
    && selected.signal-desktop.doInstallCheck
    && !(succeeds (changed.apply "darwin-application-signatures" pkgs.zoom-us).drvPath)
    && !(succeeds (changed.apply "darwin-application-signatures" pkgs.signal-desktop).drvPath)
  );
assert accepts "1.2";
assert selected.rclone.drvPath == pkgs.rclone.drvPath;
assert accepts "1.3.9";
assert !(accepts "1.1.9");
assert !(accepts "1.4");
assert !(accepts "2.0");
assert !(succeeds (guard fixture "unreviewed" { version = "1.3"; }));
assert !(succeeds (guard fixture "reviewed" { }));
assert !(succeeds (guard (fixture // { reason = ""; }) "reviewed" { version = "1.3"; }));
assert
  !(succeeds (
    guard (
      fixture
      // {
        affectedVersions = {
          from = "2";
          until = "1";
        };
      }
    ) "reviewed" { }
  ));
assert
  !(succeeds (
    guard (
      fixture
      // {
        affectedVersions = {
          from = "1";
        };
      }
    ) "reviewed" { }
  ));
assert succeeds (guard (fixture // { affectedVersions = null; }) "reviewed" { });
# The registry checks disabled fixes without depending on lazy module consumers.
assert !(succeeds changed.review);
assert !(succeeds changedStylix.review);
assert !(succeeds (changed.apply "ghostty-bash-prompt" { version = "1.3.1"; }));
assert (changed.apply "ghostty-bash-prompt" { version = "1.3.2"; }).version == "1.3.2";
assert !(succeeds changedAnywhere.review.nixos-anywhere-ssh-host-check);
assert
  !(succeeds
    (changedAnywhere.apply "nixos-anywhere-ssh-host-check"
      inputs.nixos-anywhere.packages.${pkgs.stdenv.hostPlatform.system}.default
    ).drvPath
  );
assert !(succeeds changedHyprland.review.hyprshell-workspace-schema);
assert !(succeeds changedHyprland.review.hyprshell-workspace-identity);
assert
  !pkgs.stdenv.hostPlatform.isLinux
  || !(succeeds
    (fixes.apply "hyprshell-workspace-identity" (pkgs.hyprshell // { version = "4.10.9"; })).drvPath
  );
assert
  !pkgs.stdenv.hostPlatform.isLinux
  || !(succeeds
    (fixes.apply "hyprshell-workspace-identity" (
      pkgs.hyprshell
      // {
        src = pkgs.hyprshell.src // {
          outputHash = "unreviewed";
          hash = "unreviewed";
        };
      }
    )).drvPath
  );
assert
  !pkgs.stdenv.hostPlatform.isLinux
  ||
    selected.hyprshell.cargoTestFlags == [
      "--package"
      "hyprshell-windows-lib"
      "event_time_tests"
    ];

assert !(succeeds changedHyprland.review.hyprland-subsurface);
assert !(succeeds changedHyprland.review.hyprland-subsurface-rounding);
assert !(succeeds changedDeterminate.review);
assert !(succeeds (changedDeterminate.apply "determinate-darwin-tests" { }));
assert (homeManagerPortal portalFixture compositorFixture).drvPath == portalFixture.drvPath;
assert
  (homeManagerPortal (portalFixture.override { label = "changed"; }) compositorFixture).drvPath
  == (portalFixture.override { label = "changed"; }).drvPath;
assert
  (homeManagerPortal legacyPortalFixture compositorFixture).drvPath
  == (legacyPortalFixture.override { hyprland = compositorFixture; }).drvPath;
assert
  (homeManagerPortal (legacyPortalFixture.override { label = "changed"; }) compositorFixture).drvPath
  == (legacyPortalFixture.override {
    label = "changed";
    hyprland = compositorFixture;
  }).drvPath;
assert homeManagerPortal null compositorFixture == null;
assert !(succeeds (changedStylix.apply "stylix-nvf" inputs.stylix));
assert succeeds (moduleFixes.apply "stylix-nvf" inputs.stylix);
assert succeeds (moduleFixes.apply "home-manager-protected-apps" inputs.home-manager);
assert succeeds (moduleFixes.apply "darwin-app-management-consent" inputs.nix-darwin);
assert succeeds consentHomeReplacement;
assert !(succeeds (consentMutant (protectedCopySource + protectedCopySource)));
assert
  !(succeeds (
    consentMutant (
      builtins.replaceStrings [ "run /usr/bin/tccutil reset SystemPolicyAppBundles > /dev/null" ] [ ":" ]
        protectedCopySource
    )
  ));
assert !(succeeds (changedDarwinModule.apply "darwin-app-management-consent" inputs.nix-darwin));
assert
  !(succeeds (
    changedHomeManager.apply "home-manager-app-management-consent" {
      upstream = inputs.home-manager;
      replacement = moduleFixes.apply "home-manager-protected-apps" inputs.home-manager;
    }
  ));
assert
  !(succeeds (
    moduleFixes.apply "home-manager-app-management-consent" {
      upstream = inputs.home-manager;
      replacement = {
        disabledModules = [ ];
        imports = [ ];
      };
    }
  ));
assert succeeds (moduleFixes.apply "determinate-libgit2-module" inputs.determinate);
assert !(succeeds (changedDeterminateModule.apply "determinate-libgit2-module" inputs.determinate));
assert !(succeeds (changedHomeManager.apply "home-manager-protected-apps" inputs.home-manager));
assert !(succeeds (changedStylix.apply "stylix-rofi" inputs.stylix));
assert succeeds (moduleFixes.apply "stylix-rofi" inputs.stylix);
assert !(succeeds (changedStylix.apply "stylix-gtk-flatpak-polarity" inputs.stylix));
assert succeeds (moduleFixes.apply "stylix-gtk-flatpak-polarity" inputs.stylix);
# Platform decisions belong to the selection interface. Linux keeps the
# upstream Claude Code and deploy-rs derivations and their check settings.
assert selected.claude-code.drvPath == pkgs.claude-code.drvPath;
assert
  pkgs.stdenv.hostPlatform.isDarwin
  ||
    selected.deploy-rs.drvPath
    == inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default.drvPath;
assert pkgs.stdenv.hostPlatform.isLinux || !(overlay selected pkgs ? hyprland);
# The global scope repairs libgit2 on both platforms. Sentry remains upstream;
# Darwin additionally retains its independently reviewed functional sandbox repair.
assert
  determinateRaw.nix-everything.drvPath
  == determinateSource.packages.${determinateSystem}.default.drvPath;
assert selected.nix.drvPath == determinateExpected.drvPath;
assert selected.nix.drvPath != determinateRaw.nix-everything.drvPath;
assert
  (determinateDependency "libgit2" determinateScoped.nix-fetchers).drvPath
  == determinateLibgit.drvPath;
assert
  (determinateDependency "libgit2" determinateRaw.nix-fetchers).drvPath != determinateLibgit.drvPath;
assert
  (determinateDependency "sentry-native" determinateScoped.nix-cli).drvPath
  == (determinateDependency "sentry-native" determinateRaw.nix-cli).drvPath;
assert selected.nix.doCheck;
assert
  builtins.sort builtins.lessThan (map lib.getName selected.nix.buildInputs)
  == builtins.sort builtins.lessThan determinateGateNames;
# The flake builtin repair is confined to the developer formatter's package.
assert selected.nixf-diagnose.drvPath == pkgs.nixf-diagnose.drvPath;
assert nixfTool.drvPath != pkgs.nixf-diagnose.drvPath;
assert nixfTool.src.drvPath == pkgs.nixf-diagnose.src.drvPath;
assert nixfTool.doInstallCheck;
assert nixfTool.nixfFlakeFrontend.doCheck == pkgs.nixf.doCheck;
assert !(succeeds (changed.apply "nixf-flake-builtins" pkgs.nixf-diagnose).drvPath);
assert
  !(succeeds
    (fixes.apply "nixf-flake-builtins" (pkgs.nixf-diagnose // { version = "0.1.5"; })).drvPath
  );
assert
  !(succeeds
    (fixes.apply "nixf-flake-builtins" (
      pkgs.nixf-diagnose
      // {
        src = pkgs.nixf-diagnose.src // {
          hash = "unreviewed";
        };
      }
    )).drvPath
  );
# Keep the upstream completion corpus and hooks; repair only the invalid lists.
assert selected.nu_scripts.version == pkgs.nu_scripts.version;
assert selected.nu_scripts.src.drvPath == pkgs.nu_scripts.src.drvPath;
assert
  (builtins.length selected.nu_scripts.patches)
  == (builtins.length (pkgs.nu_scripts.patches or [ ])) + 1;
assert selected.nu_scripts.doInstallCheck;
assert !(succeeds (changed.apply "nu-scripts-pytest-lists" pkgs.nu_scripts).drvPath);
assert
  !(succeeds
    (fixes.apply "nu-scripts-pytest-lists" (pkgs.nu_scripts // { version = "0-unstable-2026-10-03"; }))
    .drvPath
  );
assert
  !(succeeds
    (fixes.apply "nu-scripts-pytest-lists" (
      pkgs.nu_scripts
      // {
        src = pkgs.nu_scripts.src // {
          hash = "unreviewed";
          outputHash = "unreviewed";
        };
      }
    )).drvPath
  );
# These release and cache fixes now resolve directly to upstream.
assert selected.typescript-language-server.drvPath == pkgs.typescript-language-server.drvPath;
assert !pkgs.stdenv.hostPlatform.isLinux || selected.qemu-user.drvPath == pkgs.qemu-user.drvPath;
assert selected.qemu.drvPath == pkgs.qemu.drvPath;
# NVIDIA's upstream recipe explicitly declares null hooks. Check both null and
# existing hooks so appending the repair never blocks evaluation or loses work.
assert succeeds (nvidiaFixture { }).drvPath;
assert succeeds nvidiaNullHooks.postInstall;
assert succeeds nvidiaNullHooks.postInstallCheck;
assert nvidiaNullHooks.doInstallCheck;
assert lib.hasPrefix "echo existing-install-hook" nvidiaExistingHooks.postInstall;
assert lib.hasPrefix "echo existing-check-hook" nvidiaExistingHooks.postInstallCheck;
assert
  !(succeeds
    (changed.apply "nvidia-bin-patchelf" (pkgs.runCommand "nvidia-hook-fixture" { } "touch $out"))
    .drvPath
  );

# The release backport is retired; the independent secret-log repair remains.
assert selected.actual-server.version == pkgs.actual-server.version;
assert
  selected.actual-server.drvPath == (fixes.apply "actual-redact-secret-log" pkgs.actual-server)
  .drvPath;
assert selected.nix-output-monitor.drvPath != pkgs.nix-output-monitor.drvPath;
assert selected.nh.drvPath != pkgs.nh.drvPath;
# Later nh versions must bypass both the patch and this fix's revision review.
assert (fixes.apply "nh-darwin-home" (nhAt "4.4.2")).drvPath != (nhAt "4.4.2").drvPath;
assert builtins.all
  (version: (fixes.apply "nh-darwin-home" (nhAt version)).drvPath == (nhAt version).drvPath)
  [
    "4.4.3"
    "4.5.0"
    "5.0.0"
  ];
assert (changed.apply "nh-darwin-home" nhFixed).drvPath == nhFixed.drvPath;
assert !(succeeds (changed.apply "nh-darwin-home" (nhAt "4.4.2")).drvPath);
assert !(succeeds changed.review.nh-darwin-home);
assert succeeds nhUpdated.review.nh-darwin-home;
assert
  (fixes.apply "nom-quadratic-build-plan" pkgs.nix-output-monitor).drvPath
  != pkgs.nix-output-monitor.drvPath;
assert !(succeeds (fixes.apply "nom-quadratic-build-plan" (nomAt "2.2.1")).drvPath);
assert !(succeeds (changed.apply "nom-quadratic-build-plan" pkgs.nix-output-monitor).drvPath);
assert
  selected.nix-output-monitor.drvPath == (fixes.apply "nom-named-activities" (
    fixes.apply "nom-quadratic-build-plan" pkgs.nix-output-monitor
  )).drvPath;
assert selected.nix-output-monitor.doCheck;
assert !(succeeds (fixes.apply "nom-named-activities" (nomAt "2.2.1")).drvPath);
assert !(succeeds (changed.apply "nom-named-activities" pkgs.nix-output-monitor).drvPath);
assert !(succeeds (changed.apply "swift-clang-hardening" pkgs.swift).drvPath);
assert
  if pkgs.stdenv.hostPlatform.isDarwin then
    selected.swift.drvPath == (fixes.apply "swift-clang-hardening" pkgs.swiftPackages.swift).drvPath
    && selected.swift.drvPath != pkgs.swift.drvPath
    &&
      builtins.all
        (
          package: builtins.elem selected.swift.drvPath (map (input: input.drvPath) package.nativeBuildInputs)
        )
        [
          selected.ocr-capture
          selected.finder-favorites
          selected.vorssaint
        ]
    && selected.finder-favorites.SWIFT_EXEC == "${selected.swift}/bin/swiftc"
  else
    # Upstream may mark a Linux compiler broken. Verify the selection boundary
    # without forcing that unsupported derivation or allowing broken packages.
    !(overlay selected pkgs ? swift) && !(overlay selected pkgs ? swiftPackages);
# Keep the upstream release; the Darwin fix only changes test prerequisites.
assert selected.prismlauncher.version == pkgs.prismlauncher.version;
assert selected.prismlauncher-unwrapped.drvPath == pkgs.prismlauncher-unwrapped.drvPath;
assert
  if pkgs.stdenv.hostPlatform.isDarwin then
    (fixes.apply "prismlauncher-darwin-tests" pkgs.prismlauncher-unwrapped).doCheck
  else
    selected.prismlauncher.drvPath == pkgs.prismlauncher.drvPath;
assert
  if pkgs.stdenv.hostPlatform.isDarwin then
    selected.prismlauncher.drvPath != pkgs.prismlauncher.drvPath
  else
    selected.prismlauncher.drvPath == pkgs.prismlauncher.drvPath;
assert lib.versionAtLeast selected.navidrome.version "0.64.0";
assert
  !pkgs.stdenv.hostPlatform.isLinux
  ||
    selected.navidrome-plugin-audiomuseai-personal.drvPath
    == inputs.nixpkgs-personal.packages.${pkgs.stdenv.hostPlatform.system}.navidrome-plugin-audiomuseai-personal.drvPath;
builtins.deepSeq fixes.review (
  builtins.deepSeq derivations {
    registry = fixes.review;
    inherit derivations;
  }
)
