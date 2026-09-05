{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  desktop = self.nixosConfigurations.desktop.config;
  desktopRtxDrmCardPath = "/dev/dri/desktop-nvidia-card";
  desktopRtxRenderPath = "/dev/dri/by-path/pci-0000:01:00.0-render";
  sunshineAppArmorTemplate = builtins.readFile ../hosts/nixos/desktop/local/apparmor/sunshine.profile;
  desktopUsbguardPolicy = desktop.services.usbguard.rules;
  desktopUsbguardRules = lib.splitString "\n" desktopUsbguardPolicy;
  disableBluetoothPairingScript = builtins.readFile ../modules/nixos/hardware/scripts/disable-bluetooth-pairing.sh;
  airpodsCardName = "bluez_card.6C_12_70_1A_3A_43";
  airpodsWirePlumber = desktop.services.pipewire.wireplumber.extraConfig."91-airpods-pro";
  airpodsRule = lib.findFirst (
    rule: lib.any (match: (match."device.name" or null) == airpodsCardName) rule.matches
  ) null airpodsWirePlumber."monitor.bluez.rules";
  # This installer-only system keeps the Disko layout under the same flake
  # evaluation contract as the deployed host, without importing it into the
  # running desktop configuration or touching any disk during checks.
  desktopDisko = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs.inputs = inputs;
    modules = [
      ../modules/nixos/hardware/storage.nix
      ../hosts/nixos/desktop/local/hardware/filesystems.nix
      ../hosts/nixos/desktop/disko-system.nix
    ];
  };
  # Keep the opt-in branch evaluated even while passthrough remains disabled
  # on the real desktop. This is configuration-only and never binds hardware.
  vfioTest = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../modules/nixos/virtualisation/libvirt.nix
      {
        system.stateVersion = "26.05";
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        networking.nftables.enable = true;
        users.users.vfio-test.isNormalUser = true;
        virtualisation.libvirtWorkstation = {
          enable = true;
          operators = [ "vfio-test" ];
          guests.windows-dev.requiredProfile = "windows-vfio";
          vfio = {
            enable = true;
            hostVideoDrivers = [ "amdgpu" ];
            hostInitrdModules = [ "amdgpu" ];
            blacklistedModules = [ "nouveau" ];
            devices = {
              gpu = {
                pciAddress = "0000:01:00.0";
                vendorDeviceId = "10de:2786";
                iommuGroup = 12;
              };
              audio = {
                pciAddress = "0000:01:00.1";
                vendorDeviceId = "10de:22bc";
                iommuGroup = 12;
              };
            };
          };
        };
      }
    ];
  };
  vfioSpecialisation = vfioTest.config.specialisation.windows-vfio.configuration;
  desktopHome = desktop.home-manager.users.ianmh;
  macbook = self.darwinConfigurations.macbook-pro-m4.config;
  macbookHome = macbook.home-manager.users.ianmh;
  desktopSpotify = desktopHome.programs.spicetify.spotifyPackage;
  macbookSpotify = macbookHome.programs.spicetify.spotifyPackage;
  hasHomePackage = name: lib.any (package: lib.getName package == name) desktopHome.home.packages;
  hasSystemPackage =
    name: lib.any (package: lib.getName package == name) desktop.environment.systemPackages;
  hasUdevPackage =
    name: lib.any (package: lib.getName package == name) desktop.services.udev.packages;
  hasMacbookHomePackage =
    name: lib.any (package: lib.getName package == name) macbookHome.home.packages;
  moonlightStreamingScript = builtins.readFile ../homes/macbook-pro-m4/local/scripts/configure-moonlight.sh;
  sharedUblockFilters = desktop.programs.chromiumPolicies.customFilterLists;
  heliumPolicies =
    builtins.fromJSON
      desktop.environment.etc."chromium/policies/managed/helium-system.json".text;
  heliumUblockSettings =
    builtins.fromJSON
      heliumPolicies."3rdparty".extensions."blockjmkbacgjkknlgpkjjiijinjdanf".adminSettings;
  desktopUblockExtensionId = desktopHome.programs.browserSuite.extensions.zen.ublockOrigin.id;
  macbookUblockExtensionId = macbookHome.programs.browserSuite.extensions.zen.ublockOrigin.id;
  zenUblockPolicy =
    desktopHome.programs.zen-browser.policies."3rdparty".Extensions.${desktopUblockExtensionId};
  zenUblockSettings = zenUblockPolicy.userSettings;
  firefoxUblockPolicy =
    macbookHome.programs.firefox.policies."3rdparty".Extensions.${macbookUblockExtensionId};
  firefoxUblockSettings = firefoxUblockPolicy.userSettings;
  firefoxExtensionSettings = macbookHome.programs.firefox.policies.ExtensionSettings;
  macbookZenExtensionSettings = macbookHome.programs.zen-browser.policies.ExtensionSettings;
  bitwardenFirefoxExtensionId = macbookHome.programs.browserSuite.extensions.shared.bitwarden.id;
  bitwardenChromiumExtensionId =
    desktopHome.programs.browserSuite.chromium.heliumExtensions.bitwarden;
  desktopBitwardenGeckoManifest = desktopHome.programs.browserSuite.shared.bitwarden.geckoManifest;
  desktopBitwardenChromiumManifest =
    desktopHome.programs.browserSuite.shared.bitwarden.chromiumManifest;
  macbookBitwardenGeckoManifest = macbookHome.programs.browserSuite.shared.bitwarden.geckoManifest;
  macbookBitwardenChromiumManifest =
    macbookHome.programs.browserSuite.shared.bitwarden.chromiumManifest;
  chromePolicies =
    builtins.fromJSON
      desktop.environment.etc."opt/chrome/policies/managed/nixos-system.json".text;
  ublockPairIsStrings = pair: lib.all builtins.isString pair;
  macbookZenExtensionNames = [
    "karakeep"
    "rakuten"
    "refinedGitHub"
    "simplifyJobs"
    "sponsorBlock"
    "ublockOrigin"
  ];
  firefoxGeckoExtensionNames = [
    "karakeep"
    "multiAccountContainers"
    "refinedGitHub"
    "simplifyJobs"
    "sponsorBlock"
    "ublockOrigin"
  ];
  rakutenExtensionId = macbookHome.programs.browserSuite.extensions.zen.rakuten.id;
  rakutenExtensionPackage = macbookHome.programs.browserSuite.extensions.zen.rakuten.package;
  managedExtensionPoliciesMatch =
    browser: home:
    let
      extensionGroups = home.programs.browserSuite.extensions;
      extensions = extensionGroups.shared // extensionGroups.${browser};
      policies =
        home.programs.${
          if browser == "firefox" then "firefox" else "zen-browser"
        }.policies.ExtensionSettings;
      expectedIds = [ "*" ] ++ map (name: extensions.${name}.id) (builtins.attrNames extensions);
      policyMatches =
        extension:
        let
          policy = policies.${extension.id};
          expectedMode =
            if extension.mode == "required" then
              "force_installed"
            else if extension.mode == "allowed" then
              "allowed"
            else
              "normal_installed";
        in
        policy.installation_mode == expectedMode
        && policy.updates_disabled == false
        && (extension.mode == "allowed") == !(policy ? install_url);
    in
    lib.sort builtins.lessThan expectedIds == lib.sort builtins.lessThan (builtins.attrNames policies)
    && policies."*" == { installation_mode = "blocked"; }
    && lib.all policyMatches (builtins.attrValues extensions);
  steamBigPicture = lib.findFirst (
    app: app.name == "Steam Big Picture"
  ) null desktop.services.sunshine.applications.apps;
  desktopMonitorName = "desc:ASUSTek COMPUTER INC PG32UCWM";
  desktopMonitorRules = lib.filter (
    rule: rule.output == desktopMonitorName
  ) desktopHome.wayland.windowManager.hyprland.settings.monitor;
  desktopHdrMonitor = lib.findFirst (rule: (rule.bitdepth or null) == 10) null desktopMonitorRules;
in
{
  flake = {
    deploy.nodes.desktop = {
      hostname = "desktop";
      sshUser = "root";
      # Keep the full desktop closure off the Mac's native Linux builder.
      # deploy-rs evaluates locally, then asks the desktop to build and activate.
      remoteBuild = true;
      activationTimeout = 600;
      confirmTimeout = 120;

      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.desktop;
      };
    };

    checks.x86_64-linux = inputs.deploy-rs.lib.x86_64-linux.deployChecks self.deploy // {
      zen-wrapper-copy-regression = desktopHome.programs.zen-browser.package;

      browser-configuration-contract =
        assert
          !lib.hasInfix "cp -P --no-preserve=mode,ownership --remove-destination" desktopHome.programs.zen-browser.package.buildCommand;
        assert lib.hasInfix "cp -P --remove-destination"
          desktopHome.programs.zen-browser.package.buildCommand;
        assert desktopHome.programs.browserSuite.defaultBrowser == "zen";
        assert macbookHome.programs.browserSuite.defaultBrowser == "zen";
        assert desktopHome.programs.browserSuite.scrolling == "natural";
        assert macbookHome.programs.browserSuite.scrolling == "natural";
        assert desktopHome.programs.zen-browser.enable;
        assert macbookHome.programs.firefox.enable;
        assert macbookHome.programs.zen-browser.enable;
        assert macbookHome.home.activation ? reconcileFirefoxInstallRegistry;
        assert lib.hasInfix "Application Support/Firefox/profiles.ini"
          macbookHome.home.activation.reconcileFirefoxInstallRegistry.data;
        assert lib.hasInfix "Profiles/default"
          macbookHome.home.activation.reconcileFirefoxInstallRegistry.data;
        assert lib.hasInfix "hm-reconcile-gecko-install-registry"
          macbookHome.home.activation.reconcileFirefoxInstallRegistry.data;
        assert
          !lib.hasInfix "reconcile_install_registry.py" macbookHome.home.activation.reconcileFirefoxInstallRegistry.data;
        assert macbookHome.home.activation ? reconcileZenInstallRegistry;
        assert lib.hasInfix "Profiles/default" macbookHome.home.activation.reconcileZenInstallRegistry.data;
        assert lib.hasInfix "hm-reconcile-gecko-install-registry"
          macbookHome.home.activation.reconcileZenInstallRegistry.data;
        assert
          !lib.hasInfix "reconcile_install_registry.py" macbookHome.home.activation.reconcileZenInstallRegistry.data;
        assert desktopHome.programs.zen-browser.package.meta.mainProgram == "zen-beta";
        assert macbookHome.programs.zen-browser.package.meta.mainProgram == "zen-beta";
        assert lib.any (
          item: item ? hmApp && item.hmApp == macbookHome.programs.zen-browser.package.applicationName
        ) macbookHome.macos.dockItems.persistentApps;
        assert
          !lib.any (
            item: item ? hmApp && item.hmApp == "Firefox Shopping"
          ) macbookHome.macos.dockItems.persistentApps;
        assert macbookHome.programs.firefox.package.meta.mainProgram == "firefox";
        assert desktopHome.programs.zen-browser.languagePacks == [ ];
        assert macbookHome.programs.firefox.languagePacks == [ ];
        assert macbookHome.programs.zen-browser.languagePacks == [ ];
        assert macbookHome.targets.darwin.defaults."org.mozilla.firefox.plist".EnterprisePoliciesEnabled;
        assert macbookHome.targets.darwin.defaults."app.zen-browser.zen".EnterprisePoliciesEnabled;
        assert desktopHome.programs.zen-browser.policies.ExtensionUpdate;
        assert macbookHome.programs.firefox.policies.ExtensionUpdate;
        assert macbookHome.programs.zen-browser.policies.ExtensionUpdate;
        assert managedExtensionPoliciesMatch "zen" desktopHome;
        assert managedExtensionPoliciesMatch "firefox" macbookHome;
        assert managedExtensionPoliciesMatch "zen" macbookHome;
        assert lib.all ublockPairIsStrings zenUblockSettings;
        assert lib.all ublockPairIsStrings firefoxUblockSettings;
        assert !(zenUblockPolicy ? advancedSettings);
        assert !(zenUblockPolicy ? adminSettings);
        assert !(zenUblockPolicy ? toOverwrite);
        assert !(firefoxUblockPolicy ? advancedSettings);
        assert !(firefoxUblockPolicy ? adminSettings);
        assert !(firefoxUblockPolicy ? toOverwrite);
        assert builtins.attrNames macbookHome.programs.browserSuite.extensions.shared == [ "bitwarden" ];
        assert
          builtins.attrNames macbookHome.programs.browserSuite.extensions.firefox
          == firefoxGeckoExtensionNames;
        assert
          builtins.attrNames macbookHome.programs.browserSuite.extensions.zen == macbookZenExtensionNames;
        assert lib.all (
          name: macbookHome.programs.browserSuite.extensions.firefox.${name}.mode == "allowed"
        ) firefoxGeckoExtensionNames;
        assert lib.all (
          name: macbookHome.programs.browserSuite.extensions.zen.${name}.mode == "allowed"
        ) macbookZenExtensionNames;
        assert
          firefoxExtensionSettings.${bitwardenFirefoxExtensionId}.installation_mode == "force_installed";
        assert lib.all (
          name:
          firefoxExtensionSettings.${
            macbookHome.programs.browserSuite.extensions.firefox.${name}.id
          }.installation_mode == "allowed"
        ) firefoxGeckoExtensionNames;
        assert builtins.hasAttr macbookUblockExtensionId macbookZenExtensionSettings;
        assert macbookZenExtensionSettings.${rakutenExtensionId}.installation_mode == "allowed";
        assert !(macbookZenExtensionSettings.${rakutenExtensionId} ? install_url);
        assert rakutenExtensionId == rakutenExtensionPackage.addonId;
        assert macbookHome.programs.browserSuite.zen.shopping.enable;
        assert macbookHome.programs.firefox.profiles.default.name == "Personal";
        assert macbookHome.programs.firefox.profiles.default.path == "default";
        assert macbookHome.programs.firefox.profiles.default.isDefault;
        assert !(macbookHome.programs.firefox.profiles ? shopping);
        assert macbookHome.programs.zen-browser.profiles.shopping.name == "Shopping";
        assert macbookHome.programs.zen-browser.profiles.shopping.path == "shopping";
        assert !macbookHome.programs.zen-browser.profiles.shopping.isDefault;
        assert macbookHome.programs.browserSuite.zen.shopping.extensions == [ "rakuten" ];
        assert !(macbookHome.programs.firefox.policies ? DisableAccounts);
        assert !(macbookHome.programs.firefox.policies ? DisableFormHistory);
        assert !(macbookHome.programs.firefox.policies ? SanitizeOnShutdown);
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."identity.fxaccounts.enabled" == false;
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."browser.formfill.enable" == false;
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."privacy.sanitize.sanitizeOnShutdown";
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."privacy.clearOnShutdown_v2.cookiesAndStorage";
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."privacy.clearOnShutdown_v2.browsingHistoryAndDownloads";
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."extensions.autoDisableScopes" == 0;
        assert macbookHome.programs.zen-browser.profiles.shopping.settings."extensions.update.enabled";
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."browser.startup.homepage"
          == "https://www.cashbackmonitor.com/";
        assert
          builtins.attrNames macbookHome.programs.zen-browser.profiles.shopping.pins == [
            "BeFrugal"
            "Cashback Monitor"
            "Rakuten"
            "TopCashback"
          ];
        assert lib.elem rakutenExtensionId
          macbookHome.programs.zen-browser.profiles.shopping.extensionButtons."nav-bar";
        assert macbookHome.home.activation ? bootstrapZenShoppingExtensions;
        assert lib.hasInfix "Profiles/shopping/extensions/${rakutenExtensionId}.xpi"
          macbookHome.home.activation.bootstrapZenShoppingExtensions.data;
        assert lib.hasInfix (builtins.unsafeDiscardStringContext "${
          rakutenExtensionPackage
        }") macbookHome.home.activation.bootstrapZenShoppingExtensions.data;
        assert !hasMacbookHomePackage "firefox-shopping-launcher";
        assert builtins.hasAttr "urls"
          macbookHome.programs.firefox.profiles.default.search.engines.google-ai-mode;
        assert builtins.hasAttr "urls"
          macbookHome.programs.zen-browser.profiles.default.search.engines.google-ai-mode;
        assert
          builtins.attrNames macbookHome.programs.firefox.profiles.default.search.engines
          == builtins.attrNames macbookHome.programs.zen-browser.profiles.default.search.engines;
        assert builtins.hasAttr "urls"
          macbookHome.programs.zen-browser.profiles.shopping.search.engines.home-manager-options;
        assert
          macbookHome.programs.firefox.profiles.default.settings."privacy.resistFingerprinting" == false;
        assert
          macbookHome.programs.zen-browser.profiles.default.settings."privacy.resistFingerprinting" == false;
        assert
          macbookHome.programs.firefox.profiles.default.settings."browser.safebrowsing.downloads.remote.enabled";
        assert
          macbookHome.programs.zen-browser.profiles.default.settings."browser.safebrowsing.downloads.remote.enabled";
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."browser.safebrowsing.downloads.remote.enabled";
        assert
          macbookHome.programs.zen-browser.profiles.shopping.settings."browser.contentblocking.category"
          == "standard";
        assert macbookHome.programs.firefox.policies.EnableTrackingProtection.Category == "strict";
        assert !macbookHome.programs.firefox.policies.EnableTrackingProtection.Locked;
        assert macbookHome.programs.zen-browser.policies.EnableTrackingProtection.Category == "strict";
        assert !macbookHome.programs.zen-browser.policies.EnableTrackingProtection.Locked;
        assert desktopHome.programs.zen-browser.policies.DNSOverHTTPS.Enabled == false;
        assert desktopHome.programs.zen-browser.policies.DNSOverHTTPS.Locked;
        assert hasHomePackage "bitwarden-desktop";
        assert hasMacbookHomePackage "bitwarden-desktop";
        assert
          macbookHome.programs.bitwardenDesktop.package.outPath
          == inputs.nixpkgs-personal.packages.aarch64-darwin.bitwarden-desktop.outPath;
        assert desktopBitwardenGeckoManifest.allowed_extensions == [ bitwardenFirefoxExtensionId ];
        assert macbookBitwardenGeckoManifest.allowed_extensions == [ bitwardenFirefoxExtensionId ];
        assert
          desktopBitwardenChromiumManifest.allowed_origins
          == [ "chrome-extension://${bitwardenChromiumExtensionId}/" ];
        assert
          macbookBitwardenChromiumManifest.allowed_origins
          == [ "chrome-extension://${bitwardenChromiumExtensionId}/" ];
        assert lib.hasSuffix "/libexec/desktop_proxy" desktopBitwardenGeckoManifest.path;
        assert lib.hasSuffix "/Bitwarden.app/Contents/MacOS/desktop_proxy"
          macbookBitwardenGeckoManifest.path;
        assert lib.elem "${bitwardenChromiumExtensionId};https://clients2.google.com/service/update2/crx"
          chromePolicies.ExtensionInstallForcelist;
        assert
          chromePolicies.ExtensionSettings.${bitwardenChromiumExtensionId}.installation_mode
          == "force_installed";
        pkgs.runCommand "browser-configuration-contract" { } "touch $out";

      azure-cli-configuration-contract =
        assert !(desktopHome.home.activation ? azureCliPreferences);
        assert !(macbookHome.home.activation ? azureCliPreferences);
        assert desktopHome.home.sessionVariables.AZURE_CORE_COLLECT_TELEMETRY == "no";
        assert desktopHome.home.sessionVariables.AZURE_CORE_DISABLE_CONFIRM_PROMPT == "no";
        assert desktopHome.home.sessionVariables.AZURE_CORE_ONLY_SHOW_ERRORS == "no";
        assert desktopHome.home.sessionVariables.AZURE_CORE_OUTPUT == "jsonc";
        assert desktopHome.home.sessionVariables.AZURE_CORE_SURVEY_MESSAGE == "no";
        assert macbookHome.home.sessionVariables.AZURE_CORE_COLLECT_TELEMETRY == "no";
        assert macbookHome.home.sessionVariables.AZURE_CORE_DISABLE_CONFIRM_PROMPT == "no";
        assert macbookHome.home.sessionVariables.AZURE_CORE_ONLY_SHOW_ERRORS == "no";
        assert macbookHome.home.sessionVariables.AZURE_CORE_OUTPUT == "jsonc";
        assert macbookHome.home.sessionVariables.AZURE_CORE_SURVEY_MESSAGE == "no";
        pkgs.runCommand "azure-cli-configuration-contract" { } "touch $out";

      desktop-configuration-contract =
        assert desktop.hardware.wooting.enable;
        assert hasSystemPackage "wootility";
        assert hasUdevPackage "wooting-udev-rules";
        assert !(lib.elem "input" desktop.users.users.ianmh.extraGroups);
        assert hasMacbookHomePackage "wootility";
        assert
          (lib.findFirst (
            package: lib.getName package == "wootility"
          ) (throw "macOS Wootility package is missing") macbookHome.home.packages).outPath
          == inputs.nixpkgs-personal.packages.aarch64-darwin.wootility.outPath;
        assert self.deploy.nodes.desktop.hostname == "desktop";
        assert self.deploy.nodes.desktop.remoteBuild;
        assert desktop.home-manager.users.ianmh.home.username == "ianmh";
        # Codex remote connections and other OpenSSH command clients send
        # POSIX-shell syntax to the account's password-database shell.
        assert desktop.users.users.ianmh.shell.shellPath == "/bin/bash";
        assert desktopHome.programs.bash.enable;
        assert !desktopHome.programs.nushell.enable;
        assert desktopHome.home.sessionVariables.SHELL == lib.getExe pkgs.bashInteractive;
        # Determinate owns the daemon and garbage collector on every system.
        # Keep its evaluation features on, its GC unshared, and Home Manager
        # from placing an upstream Nix on the user's PATH.
        assert desktop.determinate.enable;
        assert desktop.nix.settings.lazy-trees;
        assert desktop.services.fprintd.enable;
        assert lib.elem desktop.services.fprintd.package desktop.services.dbus.packages;
        assert lib.elem desktop.services.fprintd.package desktop.systemd.packages;
        assert desktop.security.pam.services."polkit-1".fprintAuth;
        assert desktop.security.pam.services.sudo.fprintAuth;
        assert desktop.security.pam.services.login.fprintAuth;
        assert desktop.security.pam.services.greetd.fprintAuth;
        assert desktop.security.pam.services.hyprlock.fprintAuth;
        assert desktop.security.pam.services."polkit-1".rules.auth.fprintd.control == "sufficient";
        assert desktop.security.pam.services.sudo.rules.auth.fprintd.control == "sufficient";
        assert desktop.security.pam.services.login.rules.auth.fprintd.control == "sufficient";
        assert desktop.security.pam.services.hyprlock.rules.auth.fprintd.control == "sufficient";
        assert desktop.nix.settings.eval-cores == 0;
        assert desktop.nix.settings.flake-registry == "";
        assert
          builtins.attrNames desktop.nix.registry == [
            "nixpkgs"
            "self"
          ];
        assert desktop.nix.registry.nixpkgs.exact;
        assert !desktop.nix.gc.automatic;
        assert lib.elem "nodiscard" desktop.fileSystems."/nix".options;
        assert lib.elem "${pkgs.util-linux}/bin/fstrim --all --minimum 1M"
          desktop.systemd.services.fstrim.serviceConfig.ExecStart;
        assert
          (builtins.fromJSON desktop.environment.etc."determinate/config.json".text).garbageCollector.strategy
          == "automatic";
        assert macbook.determinateNix.enable;
        assert !macbook.nix.enable;
        assert !macbook.system.defaults.CustomUserPreferences."com.apple.security.authorization".ignoreArd;
        assert macbook.security.pam.services.sudo_local.enable;
        assert macbook.security.pam.services.sudo_local.touchIdAuth;
        assert !macbook.security.pam.services.sudo_local.watchIdAuth;
        assert !macbook.security.pam.services.sudo_local.reattach;
        assert macbook.determinateNix.customSettings.lazy-trees;
        assert macbook.determinateNix.customSettings.eval-cores == 0;
        assert macbook.determinateNix.customSettings.flake-registry == "/etc/nix/registry.json";
        assert
          builtins.attrNames macbook.determinateNix.registry == [
            "nixpkgs"
            "self"
          ];
        assert macbook.determinateNix.registry.nixpkgs.exact;
        assert macbook.determinateNix.determinateNixd.garbageCollector.strategy == "automatic";
        assert macbook.determinateNix.determinateNixd.builder.state == "enabled";
        assert desktopHome.nix.package == null;
        assert macbookHome.nix.package == null;
        # Keep macOS policy ownership and user-facing helpers on their intended
        # side of the nix-darwin/Home Manager seam.
        assert macbook.system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates;
        assert macbook.system.defaults.NSGlobalDomain.AppleKeyboardUIMode == 2;
        assert !macbook.system.defaults.controlcenter.BatteryShowPercentage;
        assert !macbook.system.defaults.CustomUserPreferences."com.apple.Siri".StatusMenuVisible;
        assert !macbook.system.defaults.CustomUserPreferences."com.apple.Passwords".EnableMenuBarExtra;
        assert (macbook.system.defaults.CustomUserPreferences."com.apple.Spotlight" or null) == null;
        assert lib.hasInfix "com.apple.Spotlight" macbook.system.activationScripts.userDefaults.text;
        assert lib.hasInfix "MenuItemHidden" macbook.system.activationScripts.userDefaults.text;
        assert lib.hasInfix "restarting SystemUIServer after changing menu bar visibility"
          macbook.system.activationScripts.userDefaults.text;
        assert (macbook.system.defaults.CustomUserPreferences."com.apple.Safari" or null) == null;
        assert macbook.macos.preferences.motion == "instant";
        assert !macbook.macos.preferences.reduceTransparency;
        assert (macbook.system.defaults.universalaccess.reduceMotion or null) == null;
        assert (macbook.system.defaults.universalaccess.reduceTransparency or null) == null;
        assert !macbook.system.defaults.NSGlobalDomain.NSAutomaticWindowAnimationsEnabled;
        assert !macbook.system.defaults.NSGlobalDomain.NSScrollAnimationEnabled;
        assert !macbook.system.defaults.NSGlobalDomain.NSUseAnimatedFocusRing;
        assert macbook.system.defaults.NSGlobalDomain.NSWindowResizeTime == 0.001;
        assert macbook.system.defaults.dock.autohide-delay == 0.0;
        assert macbook.system.defaults.dock.autohide-time-modifier == 0.0;
        assert macbook.system.defaults.dock.expose-animation-duration == 0.0;
        assert !macbook.system.defaults.dock.launchanim;
        assert !macbook.system.defaults.dock.slow-motion-allowed;
        assert macbook.macos.preferences.instantPrivateDefaults;
        assert macbook.system.defaults.CustomUserPreferences."com.apple.finder".DisableAllAnimations;
        assert
          macbook.system.defaults.CustomUserPreferences."com.apple.dock".springboard-page-duration == 0.0;
        assert (macbookHome.targets.darwin.defaults."com.apple.SoftwareUpdate" or null) == null;
        assert macbookHome.macos.commandProfile == "native-first";
        assert macbookHome.macos.dockItems.mode == "authoritative";
        assert macbookHome.macos.finderFavorites.enable;
        assert macbookHome.macos.finderFavorites.mode == "reconcile";
        assert macbookHome.macos.finderFavorites.allowDeprecatedBackend;
        assert macbookHome.macos.finderFavorites.placement == "bottom";
        assert
          macbookHome.macos.finderFavorites.package.outPath
          == inputs.nixpkgs-personal.packages.aarch64-darwin.finder-favorites.outPath;
        assert hasMacbookHomePackage "finder-favorites";
        assert macbookHome.home.activation ? syncFinderFavorites;
        assert lib.hasInfix "finder-favorites apply" macbookHome.home.activation.syncFinderFavorites.data;
        assert
          (builtins.fromJSON macbookHome.xdg.configFile."finder-favorites/config.json".text).schemaVersion
          == 1;
        assert macbookHome.macos.ocrCapture.engine == "native";
        assert
          macbookHome.macos.ocrCapture.package.outPath
          == inputs.nixpkgs-personal.packages.aarch64-darwin.ocr-capture.outPath;
        assert hasMacbookHomePackage "ocr-capture";
        assert lib.hasInfix "OCR Capture.app" macbookHome.macos.ocrCapture.applicationPath;
        assert macbookHome.macos.ocrCapture.shortcuts.copyRegion == "cmd-shift-7";
        assert lib.hasInfix "hm-ocr-capture"
          macbookHome.programs.aerospace.settings.mode.main.binding."cmd-shift-7";
        assert macbookHome.programs.linearmouse.menuBarVisibility == "never";
        # Both profiles depend on an OS-managed nix-seal runtime and are
        # intentionally unavailable as weaker standalone Home Manager outputs.
        assert !(builtins.hasAttr "ianmh@desktop" self.homeConfigurations);
        assert !(builtins.hasAttr "ianmh@macbook-pro-m4" self.homeConfigurations);
        assert desktopHome.programs.zen-browser.enable;
        assert desktopHome.programs.helium.enable;
        assert desktopHome.wayland.windowManager.hyprland.enable;
        assert !desktopHome.programs.fuzzel.enable;
        assert desktopHome.desktop.enable;
        assert desktop.desktop.system.enable;
        assert desktop.programs.dconf.enable;
        assert desktop.services.upower.enable;
        assert desktop.services.power-profiles-daemon.enable;
        assert !desktop.programs.thunar.enable;
        assert !desktopHome.programs.waybar.enable;
        assert desktopHome.desktop.noctalia.enable;
        assert desktopHome.programs.noctalia.enable;
        assert desktopHome.programs.noctalia.systemd.enable;
        assert !desktopHome.desktop.bar.enable;
        assert !desktopHome.desktop.notifications.enable;
        assert !desktopHome.desktop.osd.enable;
        assert !desktopHome.desktop.clipboard.enable;
        assert desktop.appearance.theme == "carbon-neon-oled";
        assert desktopHome.appearance.theme == "carbon-neon-oled";
        assert desktopHome.desktop.noctalia.brightness.enableDdcutil;
        assert desktopHome.desktop.applications.networkBackend == "iwd";
        assert desktopHome.desktop.clipboard.wipeOnLock;
        assert desktopHome.desktop.wallpaper.enable;
        assert hasHomePackage "nix-seal";
        assert desktopHome.desktop.wallpaper.mode == "rotate";
        assert !desktopHome.desktop.wallpaper.sources.nasaSvs.enable;
        assert desktopHome.desktop.wallpaper.sources.nasaImageLibrary.enable;
        assert desktopHome.desktop.wallpaper.sources.nasaImageLibrary.maxCandidateRecords == 60;
        assert desktopHome.desktop.wallpaper.sources.nasaImageLibrary.minYear == 2000;
        assert desktopHome.desktop.wallpaper.sources.nasaImageLibrary.maxFileSizeMiB == 150;
        assert desktopHome.desktop.wallpaper.sources.nasaImageLibrary.minAspectRatio == 1.4;
        assert desktopHome.desktop.wallpaper.sources.nasaImageLibrary.maxAspectRatio == 2.4;
        assert desktopHome.desktop.wallpaper.sources.clevelandMuseum.enable;
        assert desktopHome.desktop.wallpaper.sources.clevelandMuseum.maxFileSizeMiB == 150;
        assert desktopHome.desktop.wallpaper.sources.clevelandMuseum.maxImages == 20;
        assert desktopHome.desktop.wallpaper.sources.wikimediaCommons.enable;
        assert desktopHome.desktop.wallpaper.sources.wikimediaCommons.maxFileSizeMiB == 150;
        assert desktopHome.desktop.wallpaper.sources.smithsonian.enable;
        assert desktopHome.desktop.wallpaper.sources.smithsonian.maxFileSizeMiB == 150;
        assert desktopHome.desktop.wallpaper.sources.smithsonian.maxCandidateRecords == 80;
        assert desktopHome.desktop.wallpaper.sources.initialFetches == 2;
        assert desktopHome.desktop.wallpaper.rotation.interval == "30min";
        assert builtins.hasAttr "noctalia" desktopHome.systemd.user.services;
        assert !(builtins.hasAttr "swaync" desktopHome.systemd.user.services);
        assert !(builtins.hasAttr "swayosd" desktopHome.systemd.user.services);
        assert !(builtins.hasAttr "cliphist" desktopHome.systemd.user.services);
        assert builtins.hasAttr "awww" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-directories" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-rotate" desktopHome.systemd.user.services;
        assert !(builtins.hasAttr "desktop-wallpaper-fetch-nasa" desktopHome.systemd.user.services);
        assert builtins.hasAttr "desktop-wallpaper-fetch-nasa-library" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-fetch-cma" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-fetch-wikimedia-commons"
          desktopHome.systemd.user.services;
        assert
          builtins.hasAttr "desktop-wallpaper-fetch-smithsonian" desktopHome.systemd.user.services
          == desktopHome.desktop.wallpaper.sources.smithsonian.enable;
        assert builtins.hasAttr "desktop-wallpaper-seed" desktopHome.systemd.user.services;
        assert builtins.hasAttr "desktop-wallpaper-rotate" desktopHome.systemd.user.timers;
        assert !(builtins.hasAttr "desktop-wallpaper-fetch-nasa" desktopHome.systemd.user.timers);
        assert builtins.hasAttr "desktop-wallpaper-fetch-nasa-library" desktopHome.systemd.user.timers;
        assert builtins.hasAttr "desktop-wallpaper-fetch-cma" desktopHome.systemd.user.timers;
        assert builtins.hasAttr "desktop-wallpaper-fetch-wikimedia-commons" desktopHome.systemd.user.timers;
        assert
          builtins.hasAttr "desktop-wallpaper-fetch-smithsonian" desktopHome.systemd.user.timers
          == desktopHome.desktop.wallpaper.sources.smithsonian.enable;
        assert builtins.hasAttr "desktop-wallpaper-seed" desktopHome.systemd.user.timers;
        assert
          desktopHome.systemd.user.timers.desktop-wallpaper-seed.Timer.Unit
          == "desktop-wallpaper-seed.service";
        assert lib.elem "desktop-wallpaper-directories.service"
          desktopHome.systemd.user.services.desktop-wallpaper-fetch-nasa-library.Unit.Requires;
        assert lib.elem "desktop-wallpaper-directories.service"
          desktopHome.systemd.user.services.desktop-wallpaper-fetch-cma.Unit.Requires;
        assert lib.elem "desktop-wallpaper-directories.service"
          desktopHome.systemd.user.services.desktop-wallpaper-fetch-wikimedia-commons.Unit.Requires;
        assert
          !desktopHome.desktop.wallpaper.sources.smithsonian.enable
          || lib.elem "desktop-wallpaper-directories.service" desktopHome.systemd.user.services.desktop-wallpaper-fetch-smithsonian.Unit.Requires;
        assert lib.elem "desktop-wallpaper-directories.service"
          desktopHome.systemd.user.services.desktop-wallpaper-rotate.Unit.Requires;
        # NixOS's Hyprlock module owns the packaged Hypridle service. Home
        # Manager supplies only its configuration and must not shadow it.
        assert desktop.services.hypridle.enable;
        assert !(builtins.hasAttr "hypridle" desktopHome.systemd.user.services);
        assert lib.any (
          command: lib.hasInfix "-c /home/ianmh/.config/hypr/hypridle.conf" command
        ) desktop.systemd.user.services.hypridle.serviceConfig.ExecStart;
        assert desktopHome.programs.hyprlock.settings.general.immediate_render;
        assert desktopHome.desktop.workflow.enable;
        assert desktopHome.desktop.workflow.workspaceCount == 10;
        assert desktopHome.desktop.workflow.terminalCommand != null;
        assert desktopHome.desktop.applications.sessionLauncher == "uwsm app --";
        assert hasHomePackage "obs-studio";
        assert hasHomePackage "satty";
        assert hasHomePackage "noctalia";
        assert !(hasHomePackage "cliphist");
        assert !(hasHomePackage "desktop-swayosd-focused");
        assert hasHomePackage "desktop-wallpaper-next";
        assert hasHomePackage "desktop-wallpaper-fetch-nasa-library";
        assert !(hasHomePackage "desktop-wallpaper-fetch-nasa");
        assert hasHomePackage "desktop-wallpaper-fetch-cma";
        assert hasHomePackage "desktop-wallpaper-fetch-wikimedia-commons";
        assert
          hasHomePackage "desktop-wallpaper-fetch-smithsonian"
          == desktopHome.desktop.wallpaper.sources.smithsonian.enable;
        assert !(hasHomePackage "desktop-wallpaper-source");
        assert lib.any (
          binding: lib.hasInfix "panel-toggle launcher" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "panel-toggle control-center" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "hl.dsp.window.close" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "workspace =" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "desktop-screenshot" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert lib.any (
          binding: lib.hasInfix "desktop-wallpaper-next" (builtins.toJSON binding)
        ) desktopHome.wayland.windowManager.hyprland.settings.bind;
        assert desktopHome.wayland.windowManager.hyprland.configType == "lua";
        assert desktopHome.wayland.windowManager.hyprland.extraConfig == "";
        # Lua-mode Home Manager currently renders legacy `KEY,VALUE` env
        # entries as one argument to `hl.env`.  UWSM owns this session, so
        # cursor settings must stay in its environment file instead.
        assert (desktopHome.wayland.windowManager.hyprland.settings.env or [ ]) == [ ];
        assert desktopHome.home.pointerCursor.enable;
        assert desktopHome.home.pointerCursor.name == "Bibata-Modern-Classic";
        assert desktopHome.home.pointerCursor.size == 24;
        assert desktopHome.home.pointerCursor.gtk.enable;
        assert desktopHome.home.pointerCursor.x11.enable;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.enable;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.cursor.enable;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.cursor.logicalSize == 16;
        assert desktopHome.wayland.windowManager.hyprland.displayScaling.cursor.resolvedSize == 24;
        assert
          desktopHome.wayland.windowManager.hyprland.displayScaling.cursor.referenceOutput
          == desktopMonitorName;
        assert desktopHome.stylix.cursor.size == 24;
        assert
          desktopHome.wayland.windowManager.hyprland.displayScaling.displays.${desktopMonitorName}.mode
          == "3840x2160@240";
        assert
          desktopHome.wayland.windowManager.hyprland.displayScaling.displays.${desktopMonitorName}.resolution
          == {
            width = 3840;
            height = 2160;
          };
        assert
          desktopHome.wayland.windowManager.hyprland.displayScaling.displays.${desktopMonitorName}.physicalSizeMm
          == {
            width = 697;
            height = 392;
          };
        assert
          !(builtins.hasAttr "SUNSHINE" desktopHome.wayland.windowManager.hyprland.displayScaling.displays);
        assert builtins.length desktopMonitorRules == 2;
        assert desktopHdrMonitor != null;
        assert desktopHdrMonitor.mode == "3840x2160@240";
        assert desktopHdrMonitor.scale == 1.5;
        assert desktopHdrMonitor.cm == "auto";
        assert desktopHdrMonitor.vrr == 2;
        # Capability detection should come from the monitor EDID. Forced
        # support would hide a cable, link-mode, or driver problem.
        assert !(desktopHdrMonitor ? supports_wide_color);
        assert !(desktopHdrMonitor ? supports_hdr);
        assert desktopHome.wayland.windowManager.hyprland.settings.config.render.cm_auto_hdr == 1;
        assert !(desktopHome.wayland.windowManager.hyprland.settings.config.render ? cm_fs_passthrough);
        assert hasHomePackage "libreoffice";
        assert hasHomePackage "mpv-with-scripts";
        assert desktopHome.programs.mpv.config."target-colorspace-hint-mode" == "source";
        assert hasHomePackage "spotify-spotx";
        assert hasMacbookHomePackage "spotify-spotx";
        assert desktopSpotify.pname == "spotify-spotx";
        assert macbookSpotify.pname == "spotify-spotx";
        assert desktopSpotify.spotxVersion == macbookSpotify.spotxVersion;
        assert lib.versionAtLeast desktopSpotify.spotxVersion desktopSpotify.spotifyVersion;
        assert macbookSpotify.signingMethod == "rcodesign-recursive-bundle";
        assert desktopHome.programs.spicetify.spicedSpotify.spotxVersion == desktopSpotify.spotxVersion;
        assert macbookHome.programs.spicetify.spicedSpotify.signingMethod == macbookSpotify.signingMethod;
        assert !desktopHome.programs.spicetify.experimentalFeatures;
        assert !macbookHome.programs.spicetify.experimentalFeatures;
        assert !(macbookHome.home.activation ? repairSpotifyDarwinAppSignature);
        assert macbookHome.home.activation ? registerSpotifyDarwinApp;
        assert lib.hasInfix "lsregister" macbookHome.home.activation.registerSpotifyDarwinApp.data;
        assert !lib.hasInfix "codesign" macbookHome.home.activation.registerSpotifyDarwinApp.data;
        assert lib.hasInfix "launchctl disable \"gui/$(/usr/bin/id -u)/com.spotify.client.startuphelper\""
          macbookHome.home.activation.disableSpotifyDarwinAutostart.data;
        assert
          desktopHome.xdg.configFile."autostart/spotify.desktop".text == ''
            [Desktop Entry]
            Type=Application
            Hidden=true
          '';
        assert !(hasHomePackage "walker");
        assert !(hasHomePackage "elephant");
        assert !(hasHomePackage "ironbar");
        assert hasHomePackage "nautilus";
        assert
          desktopHome.xdg.configFile."autostart/iwgtk-indicator.desktop".text == ''
            [Desktop Entry]
            Hidden=true
          '';
        assert !(builtins.hasAttr "walker" desktopHome.systemd.user.services);
        assert !(builtins.hasAttr "elephant" desktopHome.systemd.user.services);
        assert !(builtins.hasAttr "ironbar" desktopHome.systemd.user.services);
        assert lib.hasInfix "clipboard-clear" desktopHome.desktop.idle.onLockCommand;
        # The MiniDV tools embed their exact runtime dependencies in their
        # Nix-store wrappers, so those implementation packages deliberately do
        # not need to be exposed in the global system profile.
        assert hasSystemPackage "ghostty";
        assert hasSystemPackage "minidv-capture";
        assert hasSystemPackage "minidv-diagnose";
        assert hasSystemPackage "minidv-finalize";
        assert hasSystemPackage "minidv-transcode";
        assert hasSystemPackage "minidv-upscale";
        assert hasSystemPackage "minidv-verify";
        assert hasUdevPackage "minidv-firewire-udev-rules";
        assert lib.elem "https://nix-community.cachix.org" desktop.nix.settings.substituters;
        assert desktop.networking.nftables.enable;
        assert desktop.networking.firewall.backend == "nftables";
        assert !(lib.elem 22 desktop.networking.firewall.allowedTCPPorts);
        assert lib.hasInfix "ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert lib.hasInfix "ip6 saddr fc00::/7 tcp dport 22 accept"
          desktop.networking.firewall.extraInputRules;
        assert !desktop.services.openssh.openFirewall;
        assert desktop.networking.dnsBlocker.enable;
        assert desktop.services.blocky.enable;
        assert
          desktop.services.blocky.settings.ports.dns == [
            "127.0.0.1:5335"
            "[::1]:5335"
          ];
        assert desktop.services.blocky.settings.blocking.blockType == "nxDomain";
        assert desktop.services.blocky.settings.blocking.blockTTL == "15m";
        assert desktop.services.blocky.settings.blocking.clientGroupsBlock.default == [ "stevenblack" ];
        assert desktop.services.blocky.settings.rebindingProtection.enable;
        assert desktop.services.blocky.settings.dnssec.validate;
        assert desktop.services.blocky.settings.queryLog.type == "none";
        assert desktop.systemd.services.blocky.serviceConfig.AmbientCapabilities == "";
        assert desktop.systemd.services.blocky.serviceConfig.CapabilityBoundingSet == "";
        assert
          desktop.services.resolved.settings.Resolve.DNS == [
            "127.0.0.1:5335"
            "[::1]:5335"
          ];
        assert desktop.services.resolved.settings.Resolve.Domains == [ "~." ];
        assert desktop.services.resolved.settings.Resolve.FallbackDNS == [ ];
        assert desktop.services.resolved.settings.Resolve.DNSSEC == false;
        assert desktop.networking.resolvedBaseline.enable;
        assert !desktop.networking.unboundResolver.enable;
        assert !desktop.services.unbound.enable;
        assert desktop.services.resolved.settings.Resolve.DNSStubListener == true;
        assert desktop.services.resolved.settings.Resolve.LLMNR == false;
        assert desktop.services.resolved.settings.Resolve.MulticastDNS == false;
        assert desktop.services.resolved.settings.Resolve.ReadEtcHosts == true;
        assert desktop.services.resolved.settings.Resolve.ResolveUnicastSingleLabel == false;
        assert desktop.services.resolved.settings.Resolve.CacheFromLocalhost == false;
        assert desktop.services.resolved.settings.Resolve.DNSOverTLS == false;
        assert desktop.programs.chromiumPolicies.policies.DnsOverHttpsMode == "off";
        assert desktop.programs.chromiumPolicies.dnsOverHttpsMode == "off";
        assert
          desktopHome.programs.browserSuite.chromium.extensionUpdateUrl
          == desktop.programs.chromiumPolicies.extensionUpdateUrl;
        assert
          desktopHome.programs.browserSuite.chromium.heliumExtensions
          == desktop.programs.chromiumPolicies.heliumExtensions;
        assert desktopHome.programs.browserSuite.blocking.customFilterLists == sharedUblockFilters;
        assert desktop.programs.chromiumPolicies.targets.google-chrome.enable;
        assert !desktop.programs.chromiumPolicies.targets.google-chrome.inheritSharedPolicies;
        assert desktop.programs.chromiumPolicies.targets.google-chrome.policies.DnsOverHttpsMode == "off";
        assert
          desktop.environment.etc."opt/chrome/policies/managed/nixos-system.json".text == builtins.toJSON {
            DnsOverHttpsMode = "off";
            ExtensionInstallForcelist = [
              "${bitwardenChromiumExtensionId};https://clients2.google.com/service/update2/crx"
            ];
            ExtensionSettings.${bitwardenChromiumExtensionId} = {
              installation_mode = "force_installed";
              update_url = "https://clients2.google.com/service/update2/crx";
            };
          };
        assert desktopHome.programs.zen-browser.policies.DNSOverHTTPS.Enabled == false;
        assert desktopHome.programs.zen-browser.policies.DNSOverHTTPS.Locked;
        assert desktop.networking.performanceTuning.enable;
        assert desktop.networking.performanceTuning.congestionControl == "cubic";
        assert desktop.networking.performanceTuning.enableMtuBlackholeRecovery;
        assert desktop.networking.performanceTuning.enableSynCookies;
        assert desktop.networking.wirelessIwd.enable;
        assert desktop.networking.wireless.iwd.enable;
        assert !desktop.networking.wireless.enable;
        assert desktop.networking.useNetworkd;
        assert !desktop.networking.networkmanager.enable;
        assert desktop.networking.wireless.iwd.settings.General.EnableNetworkConfiguration == false;
        assert desktop.networking.wireless.iwd.settings.General.AddressRandomization == "disabled";
        assert desktop.networking.wireless.iwd.settings.General.AddressRandomizationRange == "full";
        assert desktop.networking.wireless.iwd.settings.General.ManagementFrameProtection == 1;
        assert desktop.networking.wireless.iwd.settings.General.DisableANQP;
        assert desktop.networking.wireless.iwd.settings.General.DisablePMKSA == false;
        assert desktop.networking.wireless.iwd.settings.Settings.AutoConnect;
        assert desktop.networking.wireless.iwd.settings.Scan.DisablePeriodicScan == false;
        assert desktop.networking.wireless.iwd.settings.General.Country == "US";
        assert desktop.networking.wireless.iwd.settings.DriverQuirks.PowerSaveDisable == "mt7921e";
        assert !(desktop.networking.wireless.iwd.settings ? IPv6);
        assert !(desktop.networking.wireless.iwd.settings ? Network);
        assert desktop.networking.wireguardBaseline.enable;
        assert desktop.networking.wireguardBaseline.backend == "networkd";
        assert desktop.networking.wireguard.useNetworkd;
        assert desktop.networking.wireguard.interfaces == { };
        assert desktop.networking.wireguardBaseline.openFirewallPorts == [ ];
        assert !desktop.networking.wireguardBaseline.allowDefaultRoutes;
        assert !lib.elem "tcp_bbr" desktop.boot.kernelModules;
        assert !(desktop.boot.kernel.sysctl ? "net.core.default_qdisc");
        assert !(desktop.boot.kernel.sysctl ? "net.ipv4.tcp_congestion_control");
        assert desktop.boot.kernel.sysctl."net.ipv4.tcp_mtu_probing" == 1;
        assert desktop.boot.kernel.sysctl."net.ipv4.tcp_syncookies" == 1;
        assert desktop.networking.fail2ban.enable;
        assert desktop.services.fail2ban.enable;
        assert desktop.services.fail2ban.banaction == "nftables-multiport";
        assert desktop.services.fail2ban.bantime == "1h";
        assert desktop.services.fail2ban.maxretry == 5;
        assert desktop.services.fail2ban.bantime-increment.enable;
        assert desktop.services.fail2ban.bantime-increment.maxtime == "7d";
        assert desktop.services.fail2ban.bantime-increment.overalljails;
        assert desktop.services.fail2ban.ignoreIP == [ ];
        assert desktop.services.fail2ban.jails.sshd.enabled;
        assert desktop.services.fail2ban.jails.DEFAULT.settings.backend == "systemd";
        assert desktop.services.fail2ban.jails.DEFAULT.settings.findtime == "15m";
        assert desktop.services.fail2ban.jails.DEFAULT.settings.usedns == "no";
        assert desktop.services.openssh.settings.LogLevel == "VERBOSE";
        assert desktop.services.openssh.ports == [ 22 ];
        assert !desktop.services.openssh.openFirewall;
        assert !desktop.services.openssh.startWhenNeeded;
        assert desktop.services.openssh.settings.PermitRootLogin == "prohibit-password";
        assert !desktop.services.openssh.settings.PasswordAuthentication;
        assert !desktop.services.openssh.settings.KbdInteractiveAuthentication;
        assert !desktop.services.openssh.settings.PermitEmptyPasswords;
        assert desktop.services.openssh.settings.PubkeyAuthentication;
        assert desktop.services.openssh.settings.AuthenticationMethods == "publickey";
        assert desktop.services.openssh.settings.UsePAM;
        assert !desktop.services.openssh.settings.AllowAgentForwarding;
        assert !desktop.services.openssh.settings.Compression;
        assert !desktop.services.openssh.settings.TCPKeepAlive;
        assert desktop.services.openssh.settings.ClientAliveInterval == 300;
        assert desktop.services.openssh.settings.ClientAliveCountMax == 3;
        assert desktop.services.openssh.settings.LoginGraceTime == 30;
        assert desktop.services.openssh.settings.MaxAuthTries == 4;
        assert desktop.services.openssh.settings.MaxStartups == "10:30:60";
        assert desktop.services.openssh.settings.PerSourceMaxStartups == 3;
        assert desktop.services.openssh.settings.PermitTunnel == "no";
        assert !desktop.services.openssh.settings.PermitUserEnvironment;
        assert desktop.services.openssh.settings.GatewayPorts == "no";
        assert !desktop.networking.tarpit.enable;
        assert !desktop.services.endlessh-go.enable;
        assert desktop.xdg.portal.enable;
        assert desktop.xdg.portal.xdgOpenUsePortal;
        assert desktop.xdg.portal.config.hyprland.default == "hyprland;gtk";
        assert desktopHome.xdg.portalHomeIntegration.enable;
        assert !desktopHome.xdg.portal.enable;
        assert !desktop.services.avahi.enable;
        assert desktop.programs.nh.enable;
        assert desktop.boot.loader.systemd-boot.enable;
        assert desktop.boot.loader.systemd-boot.editor == false;
        assert desktop.boot.loader.systemd-boot.bootCounting.enable;
        assert desktop.boot.loader.systemd-boot.configurationLimit == 12;
        assert desktop.boot.initrd.systemd.enable;
        assert desktop.boot.initrd.systemd.emergencyAccess == false;
        assert desktop.boot.tmp.useTmpfs;
        assert desktop.hardware.cpu.amd.updateMicrocode;
        assert desktop.hardware.enableRedistributableFirmware;
        assert desktop.hardware.firmwareCompression == "zstd";
        assert desktop.services.fwupd.enable;
        assert
          desktop.services.fwupd.daemonSettings.EspLocation == desktop.boot.loader.efi.efiSysMountPoint;
        assert desktop.services.fwupd.uefiCapsuleSettings.RebootCleanup;
        assert desktop.services.fwupd.uefiCapsuleSettings.RequireESPFreeSpace == 128;
        assert desktop.security.usbguardBaseline.enable;
        assert desktop.services.usbguard.enable;
        assert desktop.services.usbguard.implicitPolicyTarget == "block";
        assert lib.elem ''allow hash "BertsznnITAaNuTIVmTDexmItla4SVzIu0GewGgZp1Y="'' desktopUsbguardRules;
        assert lib.elem ''allow hash "gPI7GdWoaX0fu8DRkks2RxbY/4Mcm7qeop13NChBHCs="'' desktopUsbguardRules;
        assert lib.elem
          ''allow hash "W9IsebkP0pg7VThs+fEitiTx/3tbu6hxA9OCYTEbJFQ=" parent-hash "ZSIwGrd3P5OijFEKFFRXtBKibyl6VwegRhsvNUTUBeo=" via-port "5-2"''
          desktopUsbguardRules;
        assert lib.elem
          ''allow hash "lTjKR3xhFWlY/tcYxVeYvLJup1GD5ETcUkZrPt9e4y0=" parent-hash "WsWOWC2Sd9MdaR8y3kCnZnbsGRF7Is9LR2iaMqR4kAo=" via-port "6-2"''
          desktopUsbguardRules;
        assert lib.elem
          ''allow hash "lDfabLRo3dN1+Q5vkNjGx8UiBiDKFsDDBNgIGpTHOXQ=" parent-hash "W9IsebkP0pg7VThs+fEitiTx/3tbu6hxA9OCYTEbJFQ=" via-port "5-2.4"''
          desktopUsbguardRules;
        assert lib.elem
          ''allow hash "5qV38hE0ACWm79QYAOtGSKu9XWKXnOma2l8bhjeTCYU=" parent-hash "W9IsebkP0pg7VThs+fEitiTx/3tbu6hxA9OCYTEbJFQ=" via-port "5-2.6"''
          desktopUsbguardRules;
        assert !lib.hasInfix "090c:1000" desktopUsbguardPolicy;
        assert lib.elem "timers.target" desktop.systemd.timers.fwupd-refresh.wantedBy;
        assert desktop.hardware.bluetooth.enable;
        assert desktop.hardware.bluetooth.powerOnBoot;
        assert desktop.hardware.bluetooth.disabledPlugins == [ "sap" ];
        assert desktop.hardware.bluetooth.settings.General.ControllerMode == "dual";
        assert desktop.hardware.bluetooth.settings.General.Privacy == "device";
        assert desktop.hardware.bluetooth.settings.General.PairableTimeout == 60;
        assert desktop.hardware.bluetooth.settings.General.JustWorksRepairing == "confirm";
        assert desktop.hardware.bluetooth.settings.General.SecureConnections == "on";
        assert desktop.hardware.bluetooth.settings.General.FastConnectable;
        assert desktop.hardware.bluetooth.settings.Policy.ResumeDelay == 3;
        assert desktop.hardware.bluetooth.input.General.ClassicBondedOnly;
        assert desktop.hardware.bluetooth.input.General.LEAutoSecurity;
        assert lib.hasInfix "=~ ^hci[0-9]+$ ]] || continue" disableBluetoothPairingScript;
        assert desktop.services.blueman.enable;
        assert
          desktop.services.pipewire.wireplumber.extraConfig."10-bluetooth-policy"."wireplumber.settings"."device.routes.mute-on-bluetooth-playback-removed";
        assert !desktop.programs.librepods.enable;
        assert !lib.elem "librepods" desktop.users.users.ianmh.extraGroups;
        assert !airpodsWirePlumber."wireplumber.settings"."bluetooth.autoswitch-to-headset-profile";
        assert airpodsWirePlumber."monitor.bluez.properties"."bluez5.dummy-avrcp-player";
        assert airpodsRule != null;
        assert
          airpodsRule.actions.update-props."bluez5.auto-connect" == [
            "a2dp_sink"
            "hfp_hf"
          ];
        assert airpodsRule.actions.update-props."bluez5.a2dp.aac.bitratemode" == 5;
        assert desktop.console.earlySetup;
        assert desktop.console.useXkbConfig;
        assert desktop.services.getty.autologinUser == null;
        assert lib.all (module: lib.elem module desktop.boot.initrd.kernelModules) [
          "nvme"
          "btrfs"
        ];
        assert desktop.services.telegraf.enable;
        assert desktop.services.telegraf.extraConfig.outputs.prometheus_client.listen == "127.0.0.1:9273";
        assert desktop.security.wrappers.smartctl-telegraf.owner == "telegraf";
        assert desktop.services.openssh.settings.X11Forwarding == false;
        assert desktop.services.openssh.settings.UseDns == false;
        assert desktop.services.openssh.settings.StreamLocalBindUnlink == true;
        assert builtins.hasAttr "updateDiff" desktop.system.preSwitchChecks;
        assert lib.hasInfix "PATH=\"$incoming/sw/bin:$PATH\"" desktop.system.preSwitchChecks.updateDiff;
        assert builtins.hasAttr "expectedHostname" desktop.system.preSwitchChecks;
        assert desktop.programs.gamemode.enable;
        assert desktop.programs.gamemode.enableRenice;
        assert desktop.programs.gamemode.settings.general.softrealtime == "off";
        assert desktop.programs.gamemode.settings.general.renice == 10;
        assert desktop.programs.gamescope.enable;
        assert desktop.programs.gamescope.enableWsi;
        assert !desktop.programs.gamescope.capSysNice;
        assert lib.elem pkgs.gamescope-wsi desktop.hardware.graphics.extraPackages;
        assert lib.elem pkgs.pkgsi686Linux.gamescope-wsi desktop.hardware.graphics.extraPackages32;
        assert desktop.programs.steam.enable;
        assert desktop.programs.steam.gamescopeSession.enable;
        assert desktop.programs.steam.extest.enable;
        assert desktop.programs.steam.protontricks.enable;
        assert lib.hasInfix "STEAM_SCALE_FACTOR=1.5" desktop.programs.steam.package.profile;
        assert lib.hasInfix "lib/libsteam-cef-scale-override.so" desktop.programs.steam.package.profile;
        assert lib.hasInfix "lib/libextest.so" desktop.programs.steam.package.profile;
        assert desktop.hardware.graphics.enable32Bit;
        assert desktop.services.pipewire.enable;
        assert desktop.services.pipewire.audio.enable;
        assert desktop.services.pipewire.alsa.support32Bit;
        assert desktop.services.pipewire.pulse.enable;
        assert desktop.services.pipewire.jack.enable;
        assert desktop.services.pipewire.wireplumber.enable;
        assert desktop.security.rtkit.enable;
        assert !desktop.services.pulseaudio.enable;
        assert !lib.any (limit: limit.domain == "@audio") desktop.security.pam.loginLimits;
        assert
          desktop.services.pipewire.extraConfig.pipewire."90-desktop-low-latency"."context.properties"."default.clock.quantum"
          == 128;
        assert
          desktop.services.pipewire.extraConfig.pipewire-pulse."90-desktop-low-latency"."pulse.properties"."pulse.default.tlength"
          == "256/48000";
        assert desktop.hardware.i2c.enable;
        assert desktop.services.sunshine.enable;
        assert desktop.services.sunshine.autoStart;
        assert !desktop.services.sunshine.openFirewall;
        assert !desktop.services.sunshine.capSysAdmin;
        assert desktop.systemd.user.services.sunshine.unitConfig.ConditionUser == "ianmh";
        assert desktop.services.sunshine.settings.encoder == "nvenc";
        assert desktop.services.sunshine.settings.max_bitrate == 60000;
        assert desktop.services.sunshine.settings.av1_mode == 3;
        assert desktop.services.sunshine.settings.adapter_name == desktopRtxRenderPath;
        assert desktop.services.sunshine.settings.capture == "wlr";
        assert desktop.services.sunshine.settings.upnp == "disabled";
        assert
          desktop.services.sunshine.settings.csrf_allowed_origins
          == "https://desktop:47990,https://desktop.local:47990,https://192.168.10.178:47990";
        assert desktop.services.sunshine.settings.lan_encryption_mode == 2;
        assert steamBigPicture != null;
        assert
          steamBigPicture.detached
          == [ "${lib.getExe desktop.programs.steam.package} steam://open/bigpicture" ];
        assert !(builtins.hasAttr "prep-cmd" steamBigPicture);
        assert desktop.programs.hyprland.enable;
        assert
          desktop.programs.hyprland.package.outPath == inputs.hyprland.packages.x86_64-linux.hyprland.outPath;
        assert
          desktop.programs.hyprland.portalPackage.outPath
          == inputs.hyprland.packages.x86_64-linux.xdg-desktop-portal-hyprland.outPath;
        assert desktop.programs.hyprland.withUWSM;
        assert desktop.programs.uwsm.enable;
        assert desktop.programs.hyprland.xwayland.enable;
        assert desktopHome.wayland.windowManager.hyprland.settings.config.xwayland.force_zero_scaling;
        assert desktop.programs.hyprland.systemd.setPath.enable;
        assert !desktopHome.wayland.windowManager.hyprland.systemd.enable;
        assert desktop.services.dbus.enable;
        assert desktop.xdg.portal.enable;
        assert desktop.xdg.portal.config.hyprland.default == "hyprland;gtk";
        assert desktop.services.pipewire.enable;
        assert desktop.services.pipewire.wireplumber.enable;
        assert !(lib.hasInfix ":" desktopRtxDrmCardPath);
        assert lib.hasInfix ''SYMLINK+="dri/desktop-nvidia-card"'' desktop.services.udev.extraRules;
        assert lib.hasInfix "export AQ_DRM_DEVICES=${desktopRtxDrmCardPath}" (
          builtins.readFile ../homes/desktop/local/config/uwsm-env-hyprland
        );
        assert lib.hasInfix "/dev/dri/card[0-9]* rw," sunshineAppArmorTemplate;
        assert lib.hasInfix "/dev/dri/renderD[0-9]* rw," sunshineAppArmorTemplate;
        assert !lib.hasInfix "/dev/dri/card1 rw," sunshineAppArmorTemplate;
        assert
          !lib.hasInfix "HYPRLAND_NO_SD_VARS" (
            builtins.readFile ../homes/desktop/local/config/uwsm-env-hyprland
          );
        assert
          !lib.hasInfix "HYPRLAND_NO_SD_NOTIFY" (
            builtins.readFile ../homes/desktop/local/config/uwsm-env-hyprland
          );
        assert desktop.services.greetd.enable;
        assert !desktop.services.displayManager.gdm.enable;
        assert desktop.services.greetd.settings.initial_session.user == "ianmh";
        assert desktop.programs.hyprlock.enable;
        assert
          desktop.programs.hyprlock.package.outPath == inputs.hyprlock.packages.x86_64-linux.hyprlock.outPath;
        assert desktop.security.pam.services.hyprlock.enableGnomeKeyring;
        assert desktop.security.pam.services.passwd.enableGnomeKeyring;
        assert hasSystemPackage "seahorse";
        assert desktop.systemd.user.services.sunshine-session-lock.unitConfig.ConditionUser == "ianmh";
        assert
          desktop.systemd.user.services.sunshine-session-lock.unitConfig.After
          == [ "graphical-session.target" ];
        assert lib.hasInfix "pidof"
          desktop.systemd.user.services.sunshine-session-lock.serviceConfig.ExecStart;
        assert lib.hasInfix "Unlock desktop" desktopHome.xdg.configFile."hypr/hyprlock.conf".text;
        assert !(builtins.hasAttr "sunshine-headless-output" desktop.systemd.user.services);
        assert
          !lib.hasInfix "sunshine-headless-output.service" (
            desktop.systemd.user.services.sunshine.unitConfig.Wants or ""
          );
        assert desktop.systemd.user.services.sunshine.serviceConfig.Restart == "on-failure";
        assert desktop.systemd.user.services.sunshine.serviceConfig.RestartSec == "5s";
        assert desktop.hardware.uinput.enable;
        assert lib.elem "uinput" desktop.users.users.ianmh.extraGroups;
        assert lib.hasInfix "tcp dport { 47984, 47989, 47990, 48010 } accept"
          desktop.networking.firewall.extraInputRules;
        assert lib.hasInfix "udp dport { 47998, 47999, 48000, 48002, 48010 } accept"
          desktop.networking.firewall.extraInputRules;
        assert hasMacbookHomePackage "moonlight-qt";
        assert lib.hasInfix "width -int 2562" moonlightStreamingScript;
        assert lib.hasInfix "height -int 1656" moonlightStreamingScript;
        assert lib.hasInfix "fps -int 120" moonlightStreamingScript;
        assert lib.hasInfix "bitrate -int 55000" moonlightStreamingScript;
        assert lib.hasInfix "videocfg -int 4" moonlightStreamingScript;
        assert lib.hasInfix "hdr -bool false" moonlightStreamingScript;
        assert !desktop.virtualisation.docker.enable;
        assert desktop.virtualisation.docker.rootless.enable;
        assert desktop.users.users.ianmh.linger;
        assert !(desktop.systemd.services ? docker);
        assert desktop.systemd.user.services.docker.unitConfig.ConditionUser == "ianmh";
        assert desktop.systemd.user.services.docker.wantedBy == [ ];
        assert desktop.systemd.user.services.docker.serviceConfig.Restart == "on-failure";
        assert desktop.virtualisation.docker.rootless.daemon.settings.features.buildkit;
        assert desktop.virtualisation.docker.rootless.daemon.settings."default-cgroupns-mode" == "private";
        assert desktop.virtualisation.docker.rootless.daemon.settings."no-new-privileges";
        assert desktop.systemd.services."user@".serviceConfig.Delegate == "cpu cpuset io memory pids";
        assert desktopHome.programs.docker-cli.settings.currentContext == "rootless";
        assert
          desktopHome.programs.docker-cli.contexts.rootless.Endpoints.docker.Host
          == "unix:///run/user/1000/docker.sock";
        assert !macbookHome.services.colima.profiles.default.isService;
        assert !macbookHome.services.colima.profiles.default.isActive;
        assert !macbookHome.services.colima.profiles.default.setDockerHost;
        assert macbookHome.services.colima.colimaHomeDir == ".colima";
        assert macbookHome.services.colima.profiles.default.settings.vmType == "vz";
        assert macbookHome.services.colima.profiles.default.settings.mountType == "virtiofs";
        assert macbookHome.services.colima.profiles.default.settings.rosetta;
        assert macbookHome.services.colima.profiles.default.settings.cpu == 2;
        assert macbookHome.services.colima.profiles.default.settings.memory == 4;
        assert macbookHome.services.colima.profiles.default.settings.disk == 60;
        assert desktopHome.programs.ssh.settings."nid??????".data.StrictHostKeyChecking == "accept-new";
        assert desktopHome.programs.ssh.enable;
        assert desktopHome.programs.ssh.settings."*".data.AddKeysToAgent == "yes";
        assert !desktopHome.programs.ssh.settings."*".data.ForwardAgent;
        assert !desktopHome.programs.ssh.settings."*".data.ForwardX11;
        assert desktopHome.programs.ssh.settings."*".data.HashKnownHosts;
        assert desktopHome.programs.ssh.settings."*".data.StrictHostKeyChecking == "accept-new";
        assert desktopHome.programs.ssh.settings."*".data.UpdateHostKeys == "yes";
        assert desktopHome.programs.ssh.settings."*".data.ControlPath == "/home/ianmh/.ssh/cm/%C";
        assert macbookHome.programs.ssh.enable;
        assert macbookHome.programs.ssh.settings."*".data.AddKeysToAgent == "yes";
        assert macbookHome.programs.ssh.settings."*".data.UseKeychain == "yes";
        assert macbookHome.programs.ssh.settings."*".data.ControlPath == "/Users/ianmh/.ssh/cm/%C";
        assert desktopHome.nixSeal.enable;
        assert builtins.hasAttr "nix-access-tokens" desktopHome.nixSeal.secrets;
        assert desktop.nixSeal.enable;
        assert desktop.nixSeal.linux.volatileRuntime.enable;
        assert desktop.users.groups ? ianmh;
        assert lib.elem "ianmh" desktop.users.users.ianmh.extraGroups;
        assert
          desktop.nixSeal.secrets."nix-access-tokens".source
          == "secrets/ianhollow/users/ianmh/nix-access-tokens.age";
        assert desktop.fileSystems."/run/nix-seal".fsType == "tmpfs";
        assert lib.elem "noswap" desktop.fileSystems."/run/nix-seal".options;
        assert lib.hasInfix "nix-seal-runtime-activation"
          desktop.system.activationScripts.nixSealRuntime.text;
        assert desktop.systemd.services.nix-seal-runtime.unitConfig.RequiresMountsFor == "/run/nix-seal";
        assert lib.hasInfix "/run/nix-seal/users/ianmh" desktopHome.home.activation.nixSeal.data;
        assert !lib.hasInfix "XDG_RUNTIME_DIR is required" desktopHome.home.activation.nixSeal.data;
        assert heliumUblockSettings.userSettings.importedLists == sharedUblockFilters;
        pkgs.runCommand "desktop-configuration-contract" { } "touch $out";

      virtualisation-configuration-contract =
        let
          workstation = desktop.virtualisation.libvirtWorkstation;
          setupScript = desktop.systemd.services.libvirt-workstation-setup.serviceConfig.ExecStart;
          nftablesRules = builtins.elemAt desktop.systemd.services.nftables.serviceConfig.ExecStart 1;
          profileGuard = desktop.virtualisation.libvirtd.hooks.qemu."10-workstation-profile-guard";
          sleepInhibitorHook = desktop.virtualisation.libvirtd.hooks.qemu."20-workstation-sleep-inhibitor";
          sleepInhibitorUnit = desktop.systemd.services."libvirt-workstation-sleep-inhibit@";
          windowsSetupScript = desktop.systemd.services.libvirt-windows-vm-setup.serviceConfig.ExecStart;
          windowsTriggers = desktop.systemd.services.libvirt-windows-vm-setup.restartTriggers;
          runtimeDomain = builtins.elemAt windowsTriggers 0;
          installerDomain = builtins.elemAt windowsTriggers 1;
          windowsBootstrap = builtins.elemAt windowsTriggers 2;
          windowsBaseline = builtins.elemAt windowsTriggers 3;
          expectedRemovedAppxPackages = [
            "Clipchamp.Clipchamp"
            "Microsoft.BingNews"
            "Microsoft.BingWeather"
            "Microsoft.Copilot"
            "Microsoft.GamingApp"
            "Microsoft.GetHelp"
            "Microsoft.Getstarted"
            "Microsoft.MicrosoftOfficeHub"
            "Microsoft.MicrosoftSolitaireCollection"
            "Microsoft.OutlookForWindows"
            "Microsoft.People"
            "Microsoft.PowerAutomateDesktop"
            "Microsoft.Windows.Ai.Copilot.Provider"
            "Microsoft.Windows.DevHome"
            "Microsoft.WindowsFeedbackHub"
            "Microsoft.Xbox.TCUI"
            "Microsoft.XboxApp"
            "Microsoft.XboxGameOverlay"
            "Microsoft.XboxGamingOverlay"
            "Microsoft.XboxIdentityProvider"
            "Microsoft.XboxSpeechToTextOverlay"
            "Microsoft.YourPhone"
            "Microsoft.ZuneMusic"
            "Microsoft.ZuneVideo"
            "MicrosoftCorporationII.MicrosoftFamily"
            "MicrosoftTeams"
            "MSTeams"
          ];
          vmPackage = lib.findFirst (
            package: lib.getName package == "vm"
          ) (throw "vm package is missing") desktop.environment.systemPackages;
          windowsVmPackage = lib.findFirst (
            package: lib.getName package == "windows-vm"
          ) (throw "windows-vm package is missing") desktop.environment.systemPackages;
          setupWindowsVmPackage = lib.findFirst (
            package: lib.getName package == "setup-windows-vm"
          ) (throw "setup-windows-vm package is missing") desktop.environment.systemPackages;
        in
        assert workstation.enable;
        assert !workstation.emulateAarch64;
        assert desktop.boot.binfmt.emulatedSystems == [ "aarch64-linux" ];
        assert
          builtins.attrNames workstation.networks == [
            "dev-mgmt"
            "dev-nat"
          ];
        assert workstation.networks.dev-mgmt.mode == "isolated";
        assert workstation.networks.dev-mgmt.bridge == "virbr-mgmt";
        assert workstation.networks.dev-mgmt.reservations.windows-runtime.address == 12;
        assert workstation.networks.dev-nat.mode == "nat";
        assert workstation.networks.dev-nat.bridge == "virbr-nat";
        assert workstation.networks.dev-nat.ipv4Prefix == "192.168.124";
        assert !workstation.networks.dev-nat.allowPrivateEgress;
        assert workstation.networks.dev-nat.reservations.windows-runtime.address == 12;
        assert workstation.storage.nocow;
        assert builtins.attrNames workstation.guests == [ "windows-runtime" ];
        assert workstation.guests.windows-runtime.sshHost == "windows-runtime";
        assert !workstation.guests.windows-runtime.autostart;
        assert workstation.guests.windows-runtime.inhibitSleep;
        assert workstation.windowsVm.enable;
        assert workstation.windowsVm.name == "windows-runtime";
        assert workstation.windowsVm.resources.vcpus == 4;
        assert workstation.windowsVm.resources.memoryMiB == 8192;
        assert workstation.windowsVm.resources.diskSizeGiB == 128;
        assert workstation.windowsVm.resources.cpuShares == 512;
        assert workstation.windowsVm.administrator.name == "vmadmin";
        assert workstation.windowsVm.administrator.disableUac;
        assert workstation.windowsVm.baseline.profile == "headless-runtime";
        assert workstation.windowsVm.baseline.removeAppxPackages == expectedRemovedAppxPackages;
        assert !lib.elem "Microsoft.WindowsStore" workstation.windowsVm.baseline.removeAppxPackages;
        assert !lib.elem "Microsoft.DesktopAppInstaller" workstation.windowsVm.baseline.removeAppxPackages;
        assert !lib.elem "Microsoft.WindowsTerminal" workstation.windowsVm.baseline.removeAppxPackages;
        assert !workstation.windowsVm.autostart;
        assert workstation.windowsVm.installation.release == "25H2";
        assert workstation.windowsVm.installation.imageName == "Windows 11 Pro";
        assert workstation.windowsVm.installation.editionId == "Professional";
        assert workstation.windowsVm.installation.isoFileName == "Win11_25H2_English_x64_v2.iso";
        assert
          workstation.windowsVm.installation.isoSha256
          == "768984706B909479417B2368438909440F2967FF05C6A9195ED2667254E465E3";
        assert
          workstation.windowsVm.installation.downloadPage
          == "https://www.microsoft.com/en-us/software-download/windows11";
        assert !workstation.usbRedirection.enable;
        assert !workstation.vfio.enable;
        assert workstation.vfio.devices.rtx4070.pciAddress == "0000:01:00.0";
        assert workstation.vfio.devices.rtx4070.vendorDeviceId == "10de:2786";
        assert workstation.vfio.devices.rtx4070-audio.pciAddress == "0000:01:00.1";
        assert workstation.vfio.devices.rtx4070-audio.vendorDeviceId == "10de:22bc";
        assert workstation.vfio.hostVideoDrivers == [ "amdgpu" ];
        assert vfioSpecialisation.services.xserver.videoDrivers == [ "amdgpu" ];
        assert lib.elem "vfio_pci" vfioSpecialisation.boot.initrd.kernelModules;
        assert lib.elem "vfio-pci.ids=10de:22bc,10de:2786" vfioSpecialisation.boot.kernelParams;
        assert vfioSpecialisation.environment.etc."libvirt-workstation/profile".text == "windows-vfio\n";
        assert vfioSpecialisation.system.build.toplevel.drvPath != "";
        assert desktop.virtualisation.libvirtd.enable;
        assert desktop.virtualisation.libvirtd.allowedBridges == [ ];
        assert desktop.virtualisation.libvirtd.firewallBackend == "nftables";
        assert desktop.virtualisation.libvirtd.onBoot == "ignore";
        assert desktop.virtualisation.libvirtd.onShutdown == "shutdown";
        assert !desktop.virtualisation.libvirtd.sshProxy;
        assert desktop.virtualisation.libvirtd.qemu.package.pname == "qemu-host-cpu-only";
        assert !desktop.virtualisation.libvirtd.qemu.runAsRoot;
        assert desktop.virtualisation.libvirtd.qemu.swtpm.enable;
        assert lib.elem pkgs.virtiofsd desktop.virtualisation.libvirtd.qemu.vhostUserPackages;
        assert lib.hasInfix "seccomp_sandbox = 1" desktop.virtualisation.libvirtd.qemu.verbatimConfig;
        assert desktop.virtualisation.libvirtd.nss.enableGuest;
        assert desktop.programs.virt-manager.enable;
        assert desktop.environment.sessionVariables.LIBVIRT_DEFAULT_URI == "qemu:///system";
        assert lib.elem "libvirt-media" desktop.users.users.ianmh.extraGroups;
        assert !lib.elem "libvirtd" desktop.users.users.ianmh.extraGroups;
        assert !lib.elem "kvm" desktop.users.users.ianmh.extraGroups;
        assert lib.elem "libvirt-media" desktop.users.users.qemu-libvirtd.extraGroups;
        assert !lib.elem "virbr-mgmt" desktop.networking.firewall.trustedInterfaces;
        assert !lib.elem "virbr-nat" desktop.networking.firewall.trustedInterfaces;
        assert lib.hasInfix ''iifname "virbr-mgmt" drop'' desktop.networking.firewall.extraInputRules;
        assert lib.hasInfix ''iifname "virbr-nat" drop'' desktop.networking.firewall.extraInputRules;
        assert desktop.networking.nftables.tables ? libvirt-workstation-egress;
        assert lib.hasInfix ''iifname "virbr-nat" ip daddr''
          desktop.networking.nftables.tables.libvirt-workstation-egress.content;
        assert lib.hasInfix "192.168.0.0/16"
          desktop.networking.nftables.tables.libvirt-workstation-egress.content;
        assert lib.hasInfix "198.18.0.0/15"
          desktop.networking.nftables.tables.libvirt-workstation-egress.content;
        assert lib.hasInfix "NOPASSWD:NOSETENV" desktop.security.sudo.configFile;
        assert lib.hasInfix "/libexec/libvirt-workstation-control" desktop.security.sudo.configFile;
        assert lib.hasInfix "/libexec/libvirt-windows-vm-control" desktop.security.sudo.configFile;
        assert lib.hasInfix "systemd-inhibit" sleepInhibitorUnit.serviceConfig.ExecStart;
        assert sleepInhibitorUnit.serviceConfig.Type == "notify";
        assert sleepInhibitorUnit.serviceConfig.NotifyAccess == "all";
        assert sleepInhibitorUnit.serviceConfig.TimeoutStartSec == 15;
        assert sleepInhibitorUnit.serviceConfig.ProtectSystem == "strict";
        assert desktop.systemd.services.libvirt-workstation-setup.requires == [ "libvirtd.service" ];
        assert lib.elem "libvirt-guests.service" desktop.systemd.services.libvirt-workstation-setup.before;
        assert builtins.length desktop.systemd.services.libvirt-workstation-setup.restartTriggers == 3;
        assert
          desktop.systemd.services.libvirt-windows-vm-setup.requires
          == [ "libvirt-workstation-setup.service" ];
        assert lib.elem "libvirt-guests.service" desktop.systemd.services.libvirt-windows-vm-setup.before;
        assert builtins.length windowsTriggers == 4;
        assert hasSystemPackage "vm";
        assert hasSystemPackage "windows-vm";
        assert hasSystemPackage "setup-windows-vm";
        assert hasSystemPackage "virt-host-audit";
        assert hasSystemPackage "guestfs-tools";
        assert hasSystemPackage "virtnbdbackup";
        assert desktopHome.home.activation ? libvirtVmKey;
        assert desktopHome.programs.ssh.settings.windows-runtime.data.HostName == "192.168.123.12";
        assert desktopHome.programs.ssh.settings.windows-runtime.data.User == "vmadmin";
        assert desktopHome.programs.ssh.settings.windows-runtime.data.StrictHostKeyChecking == "yes";
        assert desktopHome.programs.ssh.settings.windows-runtime.data.BatchMode;
        assert !desktopHome.programs.ssh.settings.windows-runtime.data.ForwardAgent;
        assert !desktopHome.programs.ssh.settings.windows-runtime.data.ForwardX11;
        assert !hasMacbookHomePackage "tart";
        assert !(macbookHome.home.activation ? tartVmKey);
        assert !(macbookHome.programs.ssh.settings ? dev-arm-linux);
        assert !(macbookHome.programs.ssh.settings ? dev-darwin);
        assert !(macbookHome.programs.ssh.settings ? linux-dev);
        assert !(macbookHome.programs.ssh.settings ? arm-smoke);
        assert !(macbookHome.programs.ssh.settings ? windows-dev);
        assert macbookHome.programs.ssh.settings.windows-runtime.data.ProxyJump == "desktop";
        assert macbookHome.programs.ssh.settings.windows-runtime.data.User == "vmadmin";
        assert macbookHome.programs.ssh.settings.windows-runtime.data.StrictHostKeyChecking == "yes";
        assert !macbookHome.programs.ssh.settings.windows-runtime.data.ForwardAgent;
        assert !macbookHome.programs.ssh.settings.windows-runtime.data.ForwardX11;
        pkgs.runCommand "virtualisation-configuration-contract"
          {
            nativeBuildInputs = [
              pkgs.gnugrep
              pkgs.libxml2
              pkgs.perl
              pkgs.jq
              pkgs.powershell
              pkgs.python3
              pkgs.shellcheck
            ];
          }
          ''
            test -x ${setupScript}
            test -x ${profileGuard}
            test -x ${sleepInhibitorHook}
            test -x ${vmPackage}/bin/vm
            test -x ${windowsSetupScript}
            test -x ${windowsVmPackage}/bin/windows-vm
            test -x ${setupWindowsVmPackage}/bin/setup-windows-vm
            test -x ${nftablesRules}
            test -f ${builtins.elemAt desktop.systemd.services.libvirt-workstation-setup.restartTriggers 0}
            test -f ${builtins.elemAt desktop.systemd.services.libvirt-workstation-setup.restartTriggers 1}
            test -f ${builtins.elemAt desktop.systemd.services.libvirt-workstation-setup.restartTriggers 2}
            test -f ${runtimeDomain}
            test -f ${installerDomain}
            test -f ${windowsBootstrap}
            test -f ${windowsBaseline}
            test "$(xmllint --xpath 'string(/domain/os/type/@machine)' ${runtimeDomain})" = pc-q35-10.2
            test "$(xmllint --xpath 'string(/domain/devices/disk[@device="disk"]/target/@bus)' ${runtimeDomain})" = scsi
            test "$(xmllint --xpath 'count(/domain/devices/disk[target/@bus="scsi"]/driver/@iothread)' ${runtimeDomain})" = 0
            test "$(xmllint --xpath 'string(/domain/devices/controller[@type="scsi"][@model="virtio-scsi"]/driver/@iothread)' ${runtimeDomain})" = 1
            test "$(xmllint --xpath 'count(/domain/devices/disk[@device="cdrom"])' ${runtimeDomain})" = 0
            test "$(xmllint --xpath 'count(/domain/devices/interface)' ${runtimeDomain})" = 2
            test "$(xmllint --xpath 'count(/domain/devices/hostdev | /domain/devices/filesystem | /domain/devices/redirdev | /domain/devices/audio)' ${runtimeDomain})" = 0
            test "$(xmllint --xpath 'string(/domain/os/loader)' ${runtimeDomain})" = ${pkgs.OVMFFull.fd.firmware}
            test "$(xmllint --xpath 'string(/domain/os/loader/@readonly)' ${runtimeDomain})" = yes
            test "$(xmllint --xpath 'string(/domain/os/loader/@secure)' ${runtimeDomain})" = yes
            test "$(xmllint --xpath 'string(/domain/os/loader/@type)' ${runtimeDomain})" = pflash
            test "$(xmllint --xpath 'string(/domain/os/nvram/@template)' ${runtimeDomain})" = ${pkgs.OVMFFull.fd.variablesMs}
            test "$(xmllint --xpath 'count(/domain/devices/tpm/backend[@version="2.0"])' ${runtimeDomain})" = 1
            test "$(xmllint --xpath 'string(/domain/cputune/shares)' ${runtimeDomain})" = 512
            test "$(xmllint --xpath 'count(/domain/cputune/vcpupin)' ${runtimeDomain})" = 0
            test "$(xmllint --xpath 'string(/domain/devices/disk[@device="disk" and target/@dev="sda"]/target/@bus)' ${installerDomain})" = sata
            test "$(xmllint --xpath 'count(/domain/devices/disk[@device="cdrom"])' ${installerDomain})" = 3
            test "$(xmllint --xpath 'count(/domain/devices/disk[@device="disk" and not(readonly)])' ${installerDomain})" = 1
            test "$(xmllint --xpath 'count(/domain/devices/disk[@device="disk" and readonly])' ${installerDomain})" = 1
            test "$(xmllint --xpath 'count(/domain/devices/disk[@device="cdrom" and not(readonly)])' ${installerDomain})" = 0
            xmllint --noout ${../modules/nixos/virtualisation/windows/Autounattend.xml.in}
            test "$(xmllint --xpath 'string(//*[local-name()="ProtectYourPC"])' ${../modules/nixos/virtualisation/windows/Autounattend.xml.in})" = 3
            test "$(xmllint --xpath 'count(//*[local-name()="NetworkLocation"])' ${../modules/nixos/virtualisation/windows/Autounattend.xml.in})" = 0
            test "$(xmllint --xpath 'count(//*[local-name()="HideLocalAccountScreen"])' ${../modules/nixos/virtualisation/windows/Autounattend.xml.in})" = 0
            test "$(xmllint --xpath 'count(//*[local-name()="FirstLogonCommands"]/*[local-name()="SynchronousCommand"])' ${../modules/nixos/virtualisation/windows/Autounattend.xml.in})" = 1
            ! grep -Eq '__[A-Z0-9_]+__' ${windowsBootstrap}
            ! grep -Eq '__[A-Z0-9_]+__' ${windowsBaseline}
            grep -Eq "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBootstrap}
            grep -Eq "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBaseline}
            test "$(grep -E "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBootstrap})" = \
              "$(grep -E "^[$]RecipeFingerprint = '[0-9a-f]{64}'$" ${windowsBaseline})"
            grep -Fq "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeliveryOptimization" ${windowsBootstrap}
            grep -Fq "Name = 'DODownloadMode'; Value = 0" ${windowsBootstrap}
            grep -Fq "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System" ${windowsBootstrap}
            grep -Fq "Name = 'EnableSmartScreen'; Value = 1" ${windowsBootstrap}
            grep -Fq "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge" ${windowsBootstrap}
            grep -Fq -- "-Name 'SmartScreenEnabled' -Value 1" ${windowsBootstrap}
            ! grep -Fq 'DisableWindowsConsumerFeatures' ${windowsBootstrap}
            ! grep -Fq 'NoAutoRebootWithLoggedOnUsers' ${windowsBootstrap}
            grep -Fq 'verify_installer_topology' ${../modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in}
            grep -Fq 'verify_system_disk_file' ${../modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in}
            grep -Fq 'require_current_recipe_status' ${../modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in}
            pwsh -NoLogo -NoProfile -NonInteractive -Command '
              $failed = $false
              foreach ($path in @(
                "${windowsBootstrap}",
                "${windowsBaseline}"
              )) {
                $tokens = $null
                $errors = $null
                [System.Management.Automation.Language.Parser]::ParseFile(
                  $path,
                  [ref]$tokens,
                  [ref]$errors
                ) | Out-Null
                if ($errors.Count -gt 0) {
                  $failed = $true
                  $errors | ForEach-Object { Write-Error "''${path}:$($_.Message)" }
                }
              }
              if ($failed) { exit 1 }
            '
            shellcheck -s bash ${setupScript}
            shellcheck -s bash ${profileGuard}
            shellcheck -s bash ${sleepInhibitorHook}
            shellcheck -s bash ${vmPackage}/bin/vm
            shellcheck -s bash ${windowsSetupScript}
            shellcheck -s bash ${windowsVmPackage}/bin/windows-vm
            shellcheck -s bash -e SC2034 ${setupWindowsVmPackage}/bin/setup-windows-vm
            shellcheck -s bash ${../modules/nixos/virtualisation/scripts/libvirt-workstation-control.sh.in}
            shellcheck -s bash ${../modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in}
            shellcheck -s sh ${../homes/desktop/local/scripts/create-libvirt-vm-key.sh}
            export LIBVIRT_WORKSTATION_SETUP_TEMPLATE=${../modules/nixos/virtualisation/scripts/libvirt-workstation-setup.sh.in}
            export LIBVIRT_WINDOWS_VM_CONTROL_TEMPLATE=${../modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in}
            export WINDOWS_VM_SEED_RENDERER=${../modules/nixos/virtualisation/scripts/windows-vm-render-seed.py}
            python3 -m unittest discover \
              --start-directory ${../tests/virtualisation} \
              --pattern 'test_*.py' \
              --verbose
            touch "$out"
          '';

      desktop-disko-layout-contract =
        assert desktopDisko.config.hardware.storage.encryptedRoot.enable;
        assert
          desktopDisko.config.boot.initrd.luks.devices.cryptroot.device
          == "/dev/disk/by-partlabel/NIXOS-CRYPTROOT";
        assert desktopDisko.config.boot.initrd.luks.devices.cryptroot.allowDiscards;
        assert desktopDisko.config.fileSystems."/".device == "/dev/mapper/cryptroot";
        assert desktopDisko.config.fileSystems."/boot".device == "/dev/disk/by-partlabel/NIXOS-ESP";
        assert lib.elem "subvol=@root" desktopDisko.config.fileSystems."/".options;
        assert lib.elem "nodiscard" desktopDisko.config.fileSystems."/nix".options;
        assert lib.elem "subvol=@log" desktopDisko.config.fileSystems."/var/log".options;
        assert (builtins.head desktopDisko.config.swapDevices).device == "/swap/swapfile";
        assert (builtins.head desktopDisko.config.swapDevices).priority == -1;
        assert !(lib.any (swap: swap.device == "/dev/disk/by-label/swap") desktopDisko.config.swapDevices);
        pkgs.runCommand "desktop-disko-layout-contract" { } "touch $out";
    };
  };
}
