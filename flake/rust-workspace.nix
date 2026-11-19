# Root-owned feature helpers; package catalog and submodules stay independent.
{ pkgs }:
let
  inherit (pkgs) lib;
  # Cargo owns membership; each feature keeps its implementation beside its Nix module.
  inherit (fromTOML (builtins.readFile ../Cargo.toml)) workspace;
  manifests = map (
    member: fromTOML (builtins.readFile (../. + "/${member}/Cargo.toml"))
  ) workspace.members;
  workspacePackages = lib.listToAttrs (
    map (manifest: lib.nameValuePair manifest.package.name manifest.package) manifests
  );

  linux = crate: {
    inherit crate;
    platforms = lib.platforms.linux;
  };
  packages = {
    nativePackageSelection.crate = "native-package-selection";
    adaptiveIoCost = linux "adaptive-iocost";
    libvirtControl = linux "libvirt-control";
    fontconfigAliasTools.crate = "fontconfig-alias-tools";
    gtkCssChecker = linux "check-gtk-css" // {
      nativeAdapter = true;
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.gtk4 ];
    };
    iwdValidator = linux "validate-iwd-profile" // {
      nativeAdapter = true;
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.ell ];
    };
    tuigreetCache = linux "prepare-tuigreet-cache";
    workstationEvidence.crate = "workstation-evidence";
    spotifyPreferences.crate = "spotify-preferences";
    preparePalette.crate = "noctalia-prepare-palette";
    workspaceDispatch = linux "workspace-dispatch";
    soularrRuntimeConfig = linux "soularr-runtime-config";
    devTools = {
      crate = "nix-conf-dev-tools";
      mainProgram = "git-email-privacy";
    };
    musicApiTools = linux "music-api-tools" // {
      mainProgram = "configure-audiomuse";
    };
    heliumPreferenceDefaults.crate = "helium-preference-defaults";
    geckoInstallRegistry.crate = "hm-reconcile-gecko-install-registry";
    directoryBookmarks.crate = "sync-directory-bookmarks";
    libreofficeSettings.crate = "libreoffice-settings";
    idleInhibitor = linux "desktop-idle-inhibitor";
    bluetoothPairing = linux "disable-bluetooth-pairing";
    clipboardObserver = linux "desktop-clipboard-lock";
    buildLinuxPackage = linux "build-linux-package";
    remoteRealise.crate = "remote-realise";
    dockState.crate = "hm-dock-state";
    signSignalBundle.crate = "sign-signal-bundle";
    wallpaperTools = linux "desktop-wallpaper-tools" // {
      mainProgram = "wallpaper-policy";
    };
    trustRetirement = linux "retire-desktop-trust-preview";
    iwdMaterialize = linux "materialize-iwd-profile";
    libvirtRuntimeTools = linux "libvirt-runtime-tools" // {
      mainProgram = "libvirt-xml";
    };
    applicationRecovery = linux "application-recovery";
    clamavScanRegularFiles = linux "clamav-scan-regular-files";
    desktopStorageRuntime = linux "desktop-storage-runtime" // {
      mainProgram = "desktop-storage-retire-preview";
    };
    libvirtShutdown = linux "libvirt-shutdown" // {
      nativeAdapter = true;
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.libvirt ];
    };
    homelabServiceProtocols = linux "homelab-service-protocols" // {
      mainProgram = "bootstrap-books";
    };
    actualProtocols = linux "actual-protocols" // {
      mainProgram = "actual-identity";
    };
    aurralBootstrap = linux "bootstrap-aurral";
    googleDriveRuntime = linux "google-drive-runtime";
    codexDesktopSupervisor = linux "codex-desktop-supervisor";
    codexPressureMonitor = linux "codex-pressure-monitor" // {
      nativeBuildInputs = [ pkgs.pkg-config ];
      buildInputs = [ pkgs.sqlite ];
    };
    devWorktree.crate = "dev-worktree-internal";
    macosApplicationTools = {
      crate = "macos-application-tools";
      mainProgram = "hm-macos-applications-helper";
      nativeAdapter = true;
    };
    homelabCredentials = {
      crate = "homelab-credentials";
      mainProgram = "homelab-to-bitwarden";
    };
    macSource.crate = "mac-source";
    crxToZip.crate = "helium-crx-to-zip";
    dictationReconcile.crate = "configure-voice-dictation";
    wootingProfileShare.crate = "wooting-profile-share";
  };

  packageDefinitions = builtins.attrValues packages;
  internalCrates = [
    "nix-conf-legacy-numbers"
    "nix-conf-process"
  ];
  declaredCrates = map (package: package.crate) packageDefinitions ++ internalCrates;
  duplicates = lib.filter (
    crate: builtins.length (builtins.filter (other: other == crate) declaredCrates) > 1
  ) (lib.unique declaredCrates);
  unknownCrates = lib.subtractLists (builtins.attrNames workspacePackages) declaredCrates;
  missingCrates = lib.subtractLists declaredCrates (builtins.attrNames workspacePackages);
  supported =
    package:
    lib.meta.availableOn pkgs.stdenv.hostPlatform {
      meta.platforms = package.platforms or lib.platforms.unix;
    };
  supportedDefinitions = lib.filterAttrs (_: supported) packages;
  unsupportedCrates = map (package: package.crate) (
    builtins.filter (package: !supported package) packageDefinitions
  );
  nativeAdapters = map (package: package.crate) (
    lib.filter (package: package.nativeAdapter or false) packageDefinitions
  );
  # Cargo cannot inherit lints and override only unsafe_code. Require exact parity
  # for these adapters so new common lints cannot silently leave them behind.
  nativeAdapterLints = workspace.lints // {
    rust = workspace.lints.rust // {
      unsafe_code = "deny";
    };
  };
  lintPolicyValid = builtins.all (
    manifest:
    if lib.elem manifest.package.name nativeAdapters then
      manifest.lints == nativeAdapterLints
    else
      manifest.lints.workspace or false
  ) manifests;
  source =
    assert lib.assertMsg lintPolicyValid
      "Root Rust members must inherit workspace lints; native adapters must match all lints except unsafe_code=deny.";
    lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions (
        map (member: ../. + "/${member}") workspace.members
        ++ [
          ../Cargo.toml
          ../Cargo.lock
          ../LICENSE
          ../deny.toml
          ../clippy.toml
          ../hosts/nixos/desktop/local/homelab/credentials/remote-read-sources.sh
          ../hosts/shared/local/network.json
        ]
      );
    };
  commonBuildArgs = {
    src = source;
    cargoLock.lockFile = ../Cargo.lock;
  };
  build =
    _: package:
    let
      inherit (package) crate;
      crateVersion = workspacePackages.${crate}.version;
    in
    pkgs.rustPlatform.buildRustPackage (
      commonBuildArgs
      // {
        pname = crate;
        version = if crateVersion.workspace or false then workspace.package.version else crateVersion;
        nativeBuildInputs = package.nativeBuildInputs or [ ];
        buildInputs = package.buildInputs or [ ];
        cargoBuildFlags = [
          "--package"
          crate
        ];
        cargoTestFlags = [
          "--package"
          crate
        ];
        meta = {
          mainProgram = package.mainProgram or crate;
          license = lib.licenses.mit;
          platforms = package.platforms or lib.platforms.unix;
        };
      }
    );
in
assert lib.assertMsg (unknownCrates == [ ] && missingCrates == [ ] && duplicates == [ ]) (
  "Runtime registry must account for each workspace crate once."
  + " Unknown: ${lib.concatStringsSep ", " unknownCrates}."
  + " Missing: ${lib.concatStringsSep ", " missingCrates}."
  + " Duplicates: ${lib.concatStringsSep ", " duplicates}."
);
{
  inherit (workspace) members;
  inherit commonBuildArgs source unsupportedCrates;
  packages = lib.mapAttrs build packages;
  supportedPackages = lib.mapAttrs build supportedDefinitions;
  buildInputs = lib.unique (
    lib.concatMap (package: package.buildInputs or [ ]) (builtins.attrValues supportedDefinitions)
  );
  nativeBuildInputs = lib.unique (
    lib.concatMap (package: package.nativeBuildInputs or [ ]) (builtins.attrValues supportedDefinitions)
  );
  version = workspace.package.version;
}
