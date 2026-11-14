{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  workstation = config.virtualisation.libvirtWorkstation;
  cfg = workstation.windowsVm;

  inherit (lib)
    concatMapStrings
    concatStringsSep
    escapeShellArg
    getExe
    getExe'
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  libvirtUri = "qemu:///system";
  uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$";
  sha256Pattern = "^[0-9a-fA-F]{64}$";
  windowsNamePattern = "^[A-Za-z][A-Za-z0-9._-]{0,19}$";
  computerNamePattern = "^[A-Za-z][A-Za-z0-9-]{0,14}$";
  isoFilePattern = "^[A-Za-z0-9][A-Za-z0-9._-]*[.]iso$";
  appxPackagePattern = "^[A-Za-z0-9][A-Za-z0-9._-]*$";
  protectedAppxPackages = [
    "Microsoft.AAD.BrokerPlugin"
    "Microsoft.AccountsControl"
    "Microsoft.CloudExperienceHost"
    "Microsoft.DesktopAppInstaller"
    "Microsoft.LockApp"
    "Microsoft.MicrosoftEdge.Stable"
    "Microsoft.SecHealthUI"
    "Microsoft.ShellExperienceHost"
    "Microsoft.StartMenuExperienceHost"
    "Microsoft.StorePurchaseApp"
    "Microsoft.Windows.CloudExperienceHost"
    "Microsoft.Windows.Search"
    "Microsoft.Windows.SecHealthUI"
    "Microsoft.Windows.ShellExperienceHost"
    "Microsoft.Windows.StartMenuExperienceHost"
    "Microsoft.WindowsStore"
    "Microsoft.WindowsTerminal"
    "MicrosoftWindows.Client.CBS"
    "MicrosoftWindows.Client.Core"
    "MicrosoftWindows.Client.CoreAI"
    "MicrosoftWindows.Client.FileExp"
    "MicrosoftWindows.Client.OOBE"
    "MicrosoftWindows.Client.WebExperience"
  ];
  protectedAppxPrefixes = [
    "Microsoft.NET.Native."
    "Microsoft.UI.Xaml."
    "Microsoft.VCLibs."
    "Microsoft.WindowsAppRuntime."
  ];
  normalizedProtectedAppxPackages = map lib.toLower protectedAppxPackages;
  normalizedProtectedAppxPrefixes = map lib.toLower protectedAppxPrefixes;
  isProtectedAppxPackage =
    packageName:
    let
      normalizedPackageName = lib.toLower packageName;
    in
    lib.elem normalizedPackageName normalizedProtectedAppxPackages
    || lib.any (prefix: lib.hasPrefix prefix normalizedPackageName) normalizedProtectedAppxPrefixes;
  reservedWindowsAccountNames = [
    "administrator"
    "defaultaccount"
    "guest"
    "local service"
    "network service"
    "none"
    "system"
    "wdagutilityaccount"
  ];

  diskPath = "${workstation.storage.root}/${cfg.name}.qcow2";
  isoPath = "${workstation.storage.installationMedia}/${cfg.installation.isoFileName}";
  isoSha256Path = "${isoPath}.sha256";
  stateDirectory = "/var/lib/libvirt/workstation/${cfg.name}";
  privateDirectory = "/var/lib/libvirt/private/${cfg.name}";
  runtimeDirectory = "/run/libvirt-workstation/${cfg.name}";
  passwordFile = "${runtimeDirectory}/administrator-password";
  authorizedKeysFile = "${stateDirectory}/authorized_keys";
  installMarker = "${stateDirectory}/installing";
  seedIso = "${runtimeDirectory}/answer.iso";
  primeDisk = "${runtimeDirectory}/virtio-prime.raw";
  nvramPath = "/var/lib/libvirt/qemu/nvram/${cfg.name}_VARS.fd";
  secureBootFirmware = pkgs.OVMFFull.fd;
  # Use the immutable store object in domain XML and privileged verification.
  # /etc/libvirt/virtio-win.iso remains a convenient human-facing symlink.
  virtioIso = pkgs.virtio-win.src;
  qemuPackage = config.virtualisation.libvirtd.qemu.package;
  qemuUser = "qemu-libvirtd";
  qemuGroup = "qemu-libvirtd";
  mediaInspectorUser = "windows-media";
  mediaInspectorGroup = "windows-media";
  mediaInspectionDirectory = "/var/tmp/libvirt-windows-media/${cfg.name}";
  windowsPartitionMiB = cfg.resources.diskSizeGiB * 1024 - 1300;
  activeHoursDuration =
    if cfg.maintenance.activeHoursEnd > cfg.maintenance.activeHoursStart then
      cfg.maintenance.activeHoursEnd - cfg.maintenance.activeHoursStart
    else
      24 - cfg.maintenance.activeHoursStart + cfg.maintenance.activeHoursEnd;
  enableLua = if cfg.administrator.disableUac then "0" else "1";
  normalizedIsoSha256 = lib.toLower cfg.installation.isoSha256;
  headlessRuntimeProfile = cfg.baseline.profile == "headless-runtime";
  baselineVersion = "5";
  renderedAppxPackages = concatStringsSep ",\n" (
    map (packageName: "    '${packageName}'") cfg.baseline.removeAppxPackages
  );
  answerTemplateSource = builtins.readFile ./windows/Autounattend.xml.in;
  bootstrapTemplateSource = builtins.readFile ./windows/Bootstrap.ps1.in;
  baselineTestSource = builtins.readFile ./windows/Test-Baseline.ps1.in;

  # This deliberately excludes private provisioning data and credentials. It
  # lets the host distinguish a PASS from the currently declared public recipe
  # from a stale PASS left by an older configuration.
  recipeFingerprint = builtins.hashString "sha256" (
    builtins.toJSON {
      schema = "managed-windows-vm-recipe-v1";
      sources = {
        answer = answerTemplateSource;
        bootstrap = bootstrapTemplateSource;
        test = baselineTestSource;
      };
      configuration = {
        inherit baselineVersion;
        administrator = { inherit (cfg.administrator) disableUac name; };
        inherit (cfg) computerName diskSerial;
        inherit (cfg) baseline;
        installation = {
          inherit (cfg.installation)
            editionId
            imageName
            locale
            release
            timeZone
            ;
          isoSha256 = normalizedIsoSha256;
        };
        inherit (cfg) maintenance;
        management = {
          guestAddress = managementGuestAddress;
          hostAddress = managementHostAddress;
        };
        inherit windowsPartitionMiB;
      };
    }
  );

  managementNetwork = workstation.networks.${cfg.managementNetwork};
  managementHostAddress = "${managementNetwork.ipv4Prefix}.1";
  managementGuestAddress = "${managementNetwork.ipv4Prefix}.${
    toString managementNetwork.reservations.${cfg.name}.address
  }";

  networkDevices = concatMapStrings (
    networkName:
    let
      reservation = workstation.networks.${networkName}.reservations.${cfg.name};
    in
    ''
      <interface type="network">
        <mac address="${lib.toLower reservation.macAddress}"/>
        <source network="${networkName}"/>
        <model type="virtio"/>
        <driver name="vhost" queues="2"/>
      </interface>
    ''
  ) cfg.networks;

  answerTemplate = pkgs.writeText "${cfg.name}-Autounattend.xml.in" (
    builtins.replaceStrings
      [
        "__ADMINISTRATOR_NAME__"
        "__COMPUTER_NAME__"
        "__IMAGE_NAME__"
        "__LOCALE__"
        "__TIME_ZONE__"
        "__WINDOWS_PARTITION_MIB__"
      ]
      [
        cfg.administrator.name
        cfg.computerName
        (lib.escapeXML cfg.installation.imageName)
        cfg.installation.locale
        (lib.escapeXML cfg.installation.timeZone)
        (toString windowsPartitionMiB)
      ]
      answerTemplateSource
  );

  writePowerShell = myLib.writers.writePowerShell {
    inherit pkgs;
    # These are private unattended provisioning steps. Offering WhatIf for
    # individual helpers would imply a dry run while other steps still mutate.
    excludeRules = [ "PSUseShouldProcessForStateChangingFunctions" ];
  };

  bootstrapScript = writePowerShell "${cfg.name}-Bootstrap.ps1" (
    builtins.replaceStrings
      [
        "__ACTIVE_HOURS_END__"
        "__ACTIVE_HOURS_START__"
        "__ADMINISTRATOR_NAME__"
        "__BASELINE_VERSION__"
        "__BASELINE_PROFILE__"
        "__ENABLE_LUA__"
        "__HEADLESS_RUNTIME__"
        "__MANAGEMENT_GUEST_ADDRESS__"
        "__MANAGEMENT_HOST_ADDRESS__"
        "__RECIPE_FINGERPRINT__"
        "__REMOVE_APPX_PACKAGES__"
        "__WINDOWS_RELEASE__"
      ]
      [
        (toString cfg.maintenance.activeHoursEnd)
        (toString cfg.maintenance.activeHoursStart)
        cfg.administrator.name
        baselineVersion
        cfg.baseline.profile
        enableLua
        (if headlessRuntimeProfile then "$true" else "$false")
        managementGuestAddress
        managementHostAddress
        recipeFingerprint
        renderedAppxPackages
        cfg.installation.release
      ]
      bootstrapTemplateSource
  );

  baselineTest = writePowerShell "${cfg.name}-Test-Baseline.ps1" (
    builtins.replaceStrings
      [
        "__ADMINISTRATOR_NAME__"
        "__ACTIVE_HOURS_END__"
        "__ACTIVE_HOURS_START__"
        "__BASELINE_PROFILE__"
        "__EDITION_ID__"
        "__ENABLE_LUA__"
        "__HEADLESS_RUNTIME__"
        "__MANAGEMENT_GUEST_ADDRESS__"
        "__MANAGEMENT_HOST_ADDRESS__"
        "__RECIPE_FINGERPRINT__"
        "__REMOVE_APPX_PACKAGES__"
        "__WINDOWS_RELEASE__"
      ]
      [
        cfg.administrator.name
        (toString cfg.maintenance.activeHoursEnd)
        (toString cfg.maintenance.activeHoursStart)
        cfg.baseline.profile
        cfg.installation.editionId
        enableLua
        (if headlessRuntimeProfile then "$true" else "$false")
        managementGuestAddress
        managementHostAddress
        recipeFingerprint
        renderedAppxPackages
        cfg.installation.release
      ]
      baselineTestSource
  );

  autologonArchive = pkgs.fetchurl {
    url = "https://download.sysinternals.com/files/AutoLogon.zip";
    hash = "sha256-mkd2JOpkiKz70s78w5L6wII4OjqNscbYZ68bQQ9HMbc=";
  };

  seedRenderer = pkgs.writers.writePython3Bin "windows-vm-render-seed" {
    # Ruff owns formatting; retain the writer's other Flake8 checks.
    flakeIgnore = [ "E501" ];
  } ./scripts/windows_vm_render_seed.py;

  # Keep file-backed disks on buffered I/O, matching the running desktop guest.
  # O_DIRECT can race guest buffer changes with Btrfs checksum validation.
  # writeback honors guest flushes; threads also supports buffered installer I/O.
  runtimeDiskDevices = ''
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2" cache="writeback" io="threads" discard="unmap" detect_zeroes="unmap"/>
      <source file="${diskPath}"/>
      <target dev="sda" bus="scsi" rotation_rate="1"/>
      <serial>${cfg.diskSerial}</serial>
      <boot order="1"/>
    </disk>
  '';

  installerDiskDevices = ''
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2" cache="writeback" io="threads" discard="unmap" detect_zeroes="unmap"/>
      <source file="${diskPath}"/>
      <target dev="sda" bus="sata" rotation_rate="1"/>
      <serial>${cfg.diskSerial}</serial>
      <boot order="2"/>
    </disk>
    <disk type="file" device="disk">
      <driver name="qemu" type="raw" cache="writeback" io="threads"/>
      <source file="${primeDisk}"/>
      <target dev="sde" bus="scsi"/>
      <readonly/>
    </disk>
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <source file="${isoPath}"/>
      <target dev="sdb" bus="sata"/>
      <readonly/>
      <boot order="1"/>
    </disk>
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <source file="${virtioIso}"/>
      <target dev="sdc" bus="sata"/>
      <readonly/>
    </disk>
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <source file="${seedIso}"/>
      <target dev="sdd" bus="sata"/>
      <readonly/>
    </disk>
  '';

  mkDomainDefinition =
    installationMode:
    let
      diskDevices = if installationMode then installerDiskDevices else runtimeDiskDevices;
    in
    pkgs.writeText "${cfg.name}-${if installationMode then "installer" else "runtime"}-domain.xml" (
      (import ../../../lib/templates/text.nix) ./scripts/windows-vm-config.xml {
        cfg_name = cfg.name;
        lib_toLower_cfg_uuid = lib.toLower cfg.uuid;
        lib_toLower_cfg_generationId = lib.toLower cfg.generationId;
        toString_cfg_resources_memoryMiB = toString cfg.resources.memoryMiB;
        currentMemoryMiB = toString (
          if installationMode then cfg.resources.memoryMiB else cfg.resources.currentMemoryMiB
        );
        toString_cfg_resources_vcpus = toString cfg.resources.vcpus;
        toString_cfg_resources_cpuShares = toString cfg.resources.cpuShares;
        cfg_machine = cfg.machine;
        secureBootFirmware_firmware = secureBootFirmware.firmware;
        secureBootFirmware_variablesMs = secureBootFirmware.variablesMs;
        inherit nvramPath;
        inherit qemuPackage;
        inherit diskDevices;
        inherit networkDevices;
      }
    );

  runtimeDomainSource = mkDomainDefinition false;
  installerDomainSource = mkDomainDefinition true;

  validateDomain =
    name: source:
    pkgs.runCommand "validated-${name}-domain.xml" { } (
      (import ../../../lib/templates/text.nix) ./scripts/validate-domain-xml.sh {
        inherit source;
        getExe_config_virtualisation_libvirtd_package_virt_xml_valid = getExe' config.virtualisation.libvirtd.package "virt-xml-validate";
      }
    );

  runtimeDefinition = validateDomain "${cfg.name}-runtime" runtimeDomainSource;
  installerDefinition = validateDomain "${cfg.name}-installer" installerDomainSource;

  reconcileScript = writeBashTemplate {
    name = "libvirt-windows-vm-reconcile";
    src = ./scripts/libvirt-windows-vm-reconcile.sh.in;
    replacements = {
      autostart = if cfg.autostart then "1" else "0";
      python = getExe pkgs.python3;
      xmlHelper = ./scripts/libvirt_xml.py;
      bash = getExe pkgs.bash;
      diskPath = escapeShellArg diskPath;
      guestName = escapeShellArg cfg.name;
      guestUuid = escapeShellArg (lib.toLower cfg.uuid);
      installMarker = escapeShellArg installMarker;
      libvirtUri = escapeShellArg libvirtUri;
      runtimeDefinition = escapeShellArg runtimeDefinition;
      virsh = getExe' config.virtualisation.libvirtd.package "virsh";
    };
  };

  shutdownGuest = pkgs.writers.writePython3Bin "libvirt-shutdown" {
    libraries = [ pkgs.python3Packages.libvirt ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/libvirt_shutdown.py);

  privilegedControl = writeBashTemplate {
    name = "libvirt-windows-vm-control";
    src = ./scripts/libvirt-windows-vm-control.sh.in;
    dir = "libexec";
    replacements = {
      answerTemplate = escapeShellArg answerTemplate;
      autologonArchive = escapeShellArg autologonArchive;
      autostart = if cfg.autostart then "1" else "0";
      authorizedKeysFile = escapeShellArg authorizedKeysFile;
      python = getExe pkgs.python3;
      xmlHelper = ./scripts/libvirt_xml.py;
      base64 = getExe' pkgs.coreutils "base64";
      baselineTest = escapeShellArg baselineTest;
      bash = getExe pkgs.bash;
      bootstrapScript = escapeShellArg bootstrapScript;
      cat = getExe' pkgs.coreutils "cat";
      chmod = getExe' pkgs.coreutils "chmod";
      chown = getExe' pkgs.coreutils "chown";
      cp = getExe' pkgs.coreutils "cp";
      diskPath = escapeShellArg diskPath;
      diskSerial = escapeShellArg cfg.diskSerial;
      diskSizeGiB = toString cfg.resources.diskSizeGiB;
      downloadPage = escapeShellArg cfg.installation.downloadPage;
      env = getExe' pkgs.coreutils "env";
      find = getExe pkgs.findutils;
      grep = getExe pkgs.gnugrep;
      guestName = escapeShellArg cfg.name;
      guestUuid = escapeShellArg (lib.toLower cfg.uuid);
      imageName = escapeShellArg cfg.installation.imageName;
      install = getExe' pkgs.coreutils "install";
      installMarker = escapeShellArg installMarker;
      installerDefinition = escapeShellArg installerDefinition;
      isoPath = escapeShellArg isoPath;
      isoSha256 = normalizedIsoSha256;
      jq = getExe pkgs.jq;
      libvirtUri = escapeShellArg libvirtUri;
      mediaInspectionDirectory = escapeShellArg mediaInspectionDirectory;
      mediaInspectorGroup = escapeShellArg mediaInspectorGroup;
      mediaInspectorUser = escapeShellArg mediaInspectorUser;
      mkdir = getExe' pkgs.coreutils "mkdir";
      mktemp = getExe' pkgs.coreutils "mktemp";
      mv = getExe' pkgs.coreutils "mv";
      passwordFile = escapeShellArg passwordFile;
      primeDisk = escapeShellArg primeDisk;
      privateDirectory = escapeShellArg privateDirectory;
      recipeFingerprint = escapeShellArg recipeFingerprint;
      release = escapeShellArg cfg.installation.release;
      inherit qemuGroup;
      qemuImg = getExe' qemuPackage "qemu-img";
      inherit qemuUser;
      rm = getExe' pkgs.coreutils "rm";
      runtimeDefinition = escapeShellArg runtimeDefinition;
      runtimeDirectory = escapeShellArg runtimeDirectory;
      seedIso = escapeShellArg seedIso;
      seedRenderer = getExe seedRenderer;
      sevenZip = getExe' pkgs.p7zip "7z";
      setpriv = getExe' pkgs.util-linux "setpriv";
      sha256sum = getExe' pkgs.coreutils "sha256sum";
      shutdownGuest = getExe shutdownGuest;
      sleep = getExe' pkgs.coreutils "sleep";
      sshKeygen = getExe' pkgs.openssh "ssh-keygen";
      stateDirectory = escapeShellArg stateDirectory;
      storageRoot = escapeShellArg workstation.storage.root;
      virsh = getExe' config.virtualisation.libvirtd.package "virsh";
      virtioIso = escapeShellArg virtioIso;
      wiminfo = getExe' pkgs.wimlib "wiminfo";
      xorriso = getExe' pkgs.xorriso "xorriso";
    };
  };

  setupWizard = writeBashTemplate {
    name = "setup-windows-vm";
    src = ./scripts/setup-windows-vm.sh.in;
    dir = "bin";
    replacements = {
      guestName = cfg.name;
      imageName = escapeShellArg cfg.installation.imageName;
      isoFileName = escapeShellArg cfg.installation.isoFileName;
      isoSha256 = escapeShellArg normalizedIsoSha256;
      mediaDescription = escapeShellArg cfg.installation.mediaDescription;
      privateDirectory = escapeShellArg privateDirectory;
    };
  };

  windowsVmCli = writeBashTemplate {
    name = "windows-vm";
    src = ./scripts/windows-vm.sh.in;
    dir = "bin";
    replacements = {
      bash = getExe pkgs.bash;
      cat = getExe' pkgs.coreutils "cat";
      chmod = getExe' pkgs.coreutils "chmod";
      curl = getExe pkgs.curl;
      guestName = cfg.name;
      install = getExe' pkgs.coreutils "install";
      isoLanguage = escapeShellArg cfg.installation.isoLanguage;
      isoPath = escapeShellArg isoPath;
      isoProductId = escapeShellArg cfg.installation.isoProductId;
      isoSha256 = normalizedIsoSha256;
      isoSha256Path = escapeShellArg isoSha256Path;
      mktemp = getExe' pkgs.coreutils "mktemp";
      msdl = getExe pkgs.msdl-cli;
      mv = getExe' pkgs.coreutils "mv";
      privilegedControl = "${privilegedControl}/libexec/libvirt-windows-vm-control";
      rm = getExe' pkgs.coreutils "rm";
      setupWizard = getExe' setupWizard "setup-windows-vm";
      sha256sum = getExe' pkgs.coreutils "sha256sum";
      sshKeygen = getExe' pkgs.openssh "ssh-keygen";
      sudo = "${config.security.wrapperDir}/sudo";
    };
  };
in
{
  options.virtualisation.libvirtWorkstation.windowsVm = {
    enable = mkEnableOption "a declaratively defined, unattended Windows 11 libvirt guest";

    name = mkOption {
      type = types.strMatching "^[A-Za-z0-9][A-Za-z0-9_.-]*$";
      default = "windows-runtime";
      description = "Stable libvirt domain and disk basename.";
    };

    uuid = mkOption {
      type = types.strMatching uuidPattern;
      description = "Stable libvirt and SMBIOS UUID. Never change this after Windows activation.";
    };

    generationId = mkOption {
      type = types.strMatching uuidPattern;
      description = "Stable Windows VM generation identifier used for snapshot and restore detection.";
    };

    computerName = mkOption {
      type = types.strMatching computerNamePattern;
      default = "WIN-RUNTIME";
      description = "Windows computer name, limited to the NetBIOS-compatible 15-character form.";
    };

    diskSerial = mkOption {
      type = types.strMatching "^[A-Z0-9]{4,20}$";
      default = "WINRUNTIME001";
      description = "Stable virtual system-disk serial number.";
    };

    machine = mkOption {
      type = types.strMatching "^pc-q35-[0-9]+[.][0-9]+$";
      default = "pc-q35-10.2";
      description = "Pinned QEMU machine ABI for durable Windows virtual hardware.";
    };

    autostart = mkOption {
      type = types.bool;
      default = false;
      description = "Start Windows with libvirtd after unattended recovery has been tested.";
    };

    networks = mkOption {
      type = types.listOf types.nonEmptyStr;
      description = "Ordered libvirt network names. Each must reserve this guest's stable MAC address.";
    };

    managementNetwork = mkOption {
      type = types.nonEmptyStr;
      description = "Host-only network used for the host-restricted OpenSSH rule.";
    };

    administrator = {
      name = mkOption {
        type = types.strMatching windowsNamePattern;
        default = "vmadmin";
        description = "Local administrator used for autologon, debugging, and the private runtime.";
      };

      disableUac = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Disable UAC so every process in the administrator session gets its
          full token. This intentionally removes a Windows security boundary.
        '';
      };
    };

    baseline = {
      profile = mkOption {
        type = types.enum [
          "balanced"
          "headless-runtime"
        ];
        default = "balanced";
        description = ''
          Coherent Windows policy profile. The headless-runtime profile removes
          interactive shell overhead and browser background startup while
          preserving Windows security, update, Store, and WebView components.
        '';
      };

      removeAppxPackages = mkOption {
        type = types.listOf (types.strMatching appxPackagePattern);
        default = [ ];
        description = ''
          Exact Appx DisplayName selectors to remove from installed and
          provisioned packages. This is intentionally an explicit allowlist;
          core Windows packages must not be included.
        '';
      };
    };

    installation = {
      release = mkOption {
        type = types.nonEmptyStr;
        description = "Pinned Windows release identifier represented by the ISO.";
      };

      mediaDescription = mkOption {
        type = types.nonEmptyStr;
        description = "Human-readable description of the exact Microsoft installation media.";
      };

      downloadPage = mkOption {
        type = types.strMatching "^https://.+";
        description = ''
          Stable official source page for acquiring the ISO. This is kept
          separate from short-lived or authenticated artifact URLs.
        '';
      };

      imageName = mkOption {
        type = types.nonEmptyStr;
        description = ''
          Exact /IMAGE/NAME value from install.wim or install.esd. Media
          verification fails before installation unless this image exists.
        '';
      };

      editionId = mkOption {
        type = types.nonEmptyStr;
        description = "Expected Windows CurrentVersion EditionID after installation.";
      };

      isoFileName = mkOption {
        type = types.strMatching isoFilePattern;
        default = "windows-11.iso";
        description = "Fixed filename below the libvirt installation-media directory.";
      };

      isoProductId = mkOption {
        type = types.strMatching "^[0-9]+$";
        description = "Microsoft consumer ISO product ID selected by the pinned link resolver.";
      };

      isoLanguage = mkOption {
        type = types.nonEmptyStr;
        description = "Microsoft consumer ISO language label used by the link resolver.";
      };

      isoSha256 = mkOption {
        type = types.strMatching sha256Pattern;
        description = ''
          Exact SHA-256 published by Microsoft for the selected ISO. The
          installer refuses any staged media whose bytes do not match it.
        '';
      };

      locale = mkOption {
        type = types.strMatching "^[a-z]{2}-[A-Z]{2}$";
        default = "en-US";
        description = "Windows Setup locale.";
      };

      timeZone = mkOption {
        type = types.nonEmptyStr;
        default = "UTC";
        description = "Windows time-zone identifier.";
      };
    };

    resources = {
      vcpus = mkOption {
        type = types.ints.between 2 16;
        default = 4;
        description = "Unpinned virtual CPUs. Idle vCPUs consume no dedicated host core.";
      };

      memoryMiB = mkOption {
        type = types.ints.between 4096 24576;
        default = 8192;
        description = "Guest memory ceiling in MiB.";
      };

      currentMemoryMiB = mkOption {
        type = types.ints.between 4096 24576;
        default = cfg.resources.memoryMiB;
        defaultText = lib.literalExpression "config.virtualisation.libvirtWorkstation.windowsVm.resources.memoryMiB";
        description = ''
          Runtime guest allocation in MiB, at most memoryMiB. Changes stage the
          persistent definition for the next guest start; they do not balloon a
          running guest. Installation uses the full ceiling. A smaller value
          needs guest workload measurements: Windows ballooning does not
          guarantee automatic growth when the guest runs short of memory.
        '';
      };

      diskSizeGiB = mkOption {
        type = types.ints.between 64 1024;
        default = 128;
        description = "Sparse qcow2 virtual disk capacity in GiB.";
      };

      cpuShares = mkOption {
        type = types.ints.between 2 262144;
        default = 512;
        description = "Relative libvirt CPU shares; unused host CPU remains available to the guest.";
      };
    };

    maintenance = {
      activeHoursStart = mkOption {
        type = types.ints.between 0 23;
        default = 5;
        description = "Start of Windows Update active hours.";
      };

      activeHoursEnd = mkOption {
        type = types.ints.between 0 23;
        default = 23;
        description = "End of Windows Update active hours.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.resources.currentMemoryMiB <= cfg.resources.memoryMiB;
        message = "windowsVm.resources.currentMemoryMiB must not exceed memoryMiB.";
      }
      {
        assertion = workstation.enable;
        message = "windowsVm requires virtualisation.libvirtWorkstation.enable.";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "windowsVm currently supports an x86_64-linux KVM host only.";
      }
      {
        assertion = cfg.networks != [ ] && lib.length cfg.networks == lib.length (lib.unique cfg.networks);
        message = "windowsVm.networks must contain unique network names.";
      }
      {
        assertion = lib.all (name: builtins.hasAttr name workstation.networks) cfg.networks;
        message = "Every windowsVm network must exist in libvirtWorkstation.networks.";
      }
      {
        assertion = lib.elem cfg.managementNetwork cfg.networks;
        message = "windowsVm.managementNetwork must be one of windowsVm.networks.";
      }
      {
        assertion = (workstation.networks.${cfg.managementNetwork}.mode or null) == "isolated";
        message = "windowsVm.managementNetwork must be host-only.";
      }
      {
        assertion = lib.any (name: (workstation.networks.${name}.mode or null) == "nat") cfg.networks;
        message = "windowsVm needs one NAT network for updates and runtime egress.";
      }
      {
        assertion = lib.all (
          name: builtins.hasAttr cfg.name (workstation.networks.${name}.reservations or { })
        ) cfg.networks;
        message = "Every windowsVm network must have a reservation named after the guest.";
      }
      {
        assertion = cfg.maintenance.activeHoursStart != cfg.maintenance.activeHoursEnd;
        message = "Windows Update active-hour start and end must differ.";
      }
      {
        assertion = activeHoursDuration <= 18;
        message = "Windows Update active hours must span no more than 18 hours.";
      }
      {
        assertion = !lib.hasSuffix "." cfg.administrator.name;
        message = "windowsVm.administrator.name must not end with a period.";
      }
      {
        assertion = !lib.elem (lib.toLower cfg.administrator.name) reservedWindowsAccountNames;
        message = "windowsVm.administrator.name must not be a reserved Windows account name.";
      }
      {
        assertion = lib.toLower cfg.administrator.name != lib.toLower cfg.computerName;
        message = "The Windows administrator and computer names must differ.";
      }
      {
        assertion =
          lib.length cfg.baseline.removeAppxPackages
          == lib.length (lib.unique (map lib.toLower cfg.baseline.removeAppxPackages));
        message = "windowsVm.baseline.removeAppxPackages must not contain case-insensitive duplicates.";
      }
      {
        assertion = lib.all (
          packageName: !isProtectedAppxPackage packageName
        ) cfg.baseline.removeAppxPackages;
        message = ''
          windowsVm.baseline.removeAppxPackages contains protected security,
          shell, Store, framework, or administration infrastructure.
        '';
      }
      {
        assertion = windowsPartitionMiB >= 64236;
        message = "The Windows partition must retain at least 64,236 MiB after EFI, MSR, and recovery space.";
      }
    ];

    virtualisation.libvirtWorkstation.guests.${cfg.name} = {
      inherit (cfg) autostart;
      inhibitSleep = true;
      sshHost = cfg.name;
    };

    users = {
      groups = {
        windows-vm-provisioning = { };
        ${mediaInspectorGroup} = { };
      };
      users =
        lib.genAttrs workstation.operators (_: {
          extraGroups = [ "windows-vm-provisioning" ];
        })
        // {
          ${mediaInspectorUser} = {
            isSystemUser = true;
            group = mediaInspectorGroup;
            extraGroups = [ "libvirt-media" ];
            home = "/var/empty";
            description = "Unprivileged Windows installation-media inspector";
          };
        };
    };

    environment.systemPackages = [
      setupWizard
      windowsVmCli
    ];

    security.sudo.extraRules = map (operator: {
      users = [ operator ];
      commands = [
        {
          command = "${privilegedControl}/libexec/libvirt-windows-vm-control";
          options = [
            "NOPASSWD"
            "NOSETENV"
          ];
        }
      ];
    }) workstation.operators;

    systemd.tmpfiles.rules = [
      "d /var/lib/libvirt/workstation 0710 root ${qemuGroup} -"
      "d ${stateDirectory} 0710 root ${qemuGroup} -"
      "d /var/lib/libvirt/private 0710 root windows-vm-provisioning -"
      "d ${privateDirectory} 2770 root windows-vm-provisioning -"
      "d /run/libvirt-workstation 0710 root ${qemuGroup} -"
      "d ${runtimeDirectory} 0710 root ${qemuGroup} -"
      "d /var/tmp/libvirt-windows-media 0710 root ${mediaInspectorGroup} 1d"
      "d ${mediaInspectionDirectory} 0710 root ${mediaInspectorGroup} 1d"
    ];

    systemd.services.libvirt-windows-vm-setup = {
      description = "Reconcile the managed Windows libvirt domain";
      wantedBy = [ "multi-user.target" ];
      after = [ "libvirt-workstation-setup.service" ];
      before = [ "libvirt-guests.service" ];
      requires = [ "libvirt-workstation-setup.service" ];
      restartTriggers = [
        runtimeDefinition
        installerDefinition
        bootstrapScript
        baselineTest
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = reconcileScript;
        RemainAfterExit = true;
        UMask = "0077";
      };
    };
  };
}
