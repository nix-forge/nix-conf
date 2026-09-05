{
  config,
  lib,
  pkgs,
  ...
}:
let
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
  mediaInspectionDirectory = "/run/libvirt-windows-media/${cfg.name}";
  windowsPartitionMiB = cfg.resources.diskSizeGiB * 1024 - 1300;
  activeHoursDuration =
    if cfg.maintenance.activeHoursEnd > cfg.maintenance.activeHoursStart then
      cfg.maintenance.activeHoursEnd - cfg.maintenance.activeHoursStart
    else
      24 - cfg.maintenance.activeHoursStart + cfg.maintenance.activeHoursEnd;
  enableLua = if cfg.administrator.disableUac then "0" else "1";
  normalizedIsoSha256 = lib.toLower cfg.installation.isoSha256;
  headlessRuntimeProfile = cfg.baseline.profile == "headless-runtime";
  baselineVersion = "4";
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
        "__ENABLE_LUA__"
        "__IMAGE_NAME__"
        "__LOCALE__"
        "__TIME_ZONE__"
        "__WINDOWS_PARTITION_MIB__"
      ]
      [
        cfg.administrator.name
        cfg.computerName
        enableLua
        (lib.escapeXML cfg.installation.imageName)
        cfg.installation.locale
        (lib.escapeXML cfg.installation.timeZone)
        (toString windowsPartitionMiB)
      ]
      answerTemplateSource
  );

  bootstrapScript = pkgs.writeText "${cfg.name}-Bootstrap.ps1" (
    builtins.replaceStrings
      [
        "__ACTIVE_HOURS_END__"
        "__ACTIVE_HOURS_START__"
        "__ADMINISTRATOR_NAME__"
        "__BASELINE_VERSION__"
        "__BASELINE_PROFILE__"
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
        (if headlessRuntimeProfile then "$true" else "$false")
        managementGuestAddress
        managementHostAddress
        recipeFingerprint
        renderedAppxPackages
        cfg.installation.release
      ]
      bootstrapTemplateSource
  );

  baselineTest = pkgs.writeText "${cfg.name}-Test-Baseline.ps1" (
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

  seedRenderer = pkgs.writeShellApplication {
    name = "windows-vm-render-seed";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${./scripts/windows-vm-render-seed.py} "$@"
    '';
  };

  runtimeDiskDevices = ''
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2" cache="none" io="native" discard="unmap" detect_zeroes="unmap"/>
      <source file="${diskPath}"/>
      <target dev="sda" bus="scsi" rotation_rate="1"/>
      <serial>${cfg.diskSerial}</serial>
      <boot order="1"/>
    </disk>
  '';

  installerDiskDevices = ''
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2" cache="none" io="native" discard="unmap" detect_zeroes="unmap"/>
      <source file="${diskPath}"/>
      <target dev="sda" bus="sata" rotation_rate="1"/>
      <serial>${cfg.diskSerial}</serial>
      <boot order="2"/>
    </disk>
    <disk type="file" device="disk">
      <driver name="qemu" type="raw" cache="none" io="native"/>
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
    pkgs.writeText "${cfg.name}-${if installationMode then "installer" else "runtime"}-domain.xml" ''
      <domain type="kvm">
        <name>${cfg.name}</name>
        <uuid>${lib.toLower cfg.uuid}</uuid>
        <genid>${lib.toLower cfg.generationId}</genid>
        <title>Managed Windows runtime</title>
        <description>NixOS-managed Windows 11 guest with private runtime provisioning</description>
        <metadata>
          <managed xmlns="https://ianmh.dev/libvirt/windows-vm/1" recipe="windows-vm-v1"/>
        </metadata>
        <memory unit="MiB">${toString cfg.resources.memoryMiB}</memory>
        <currentMemory unit="MiB">${toString cfg.resources.memoryMiB}</currentMemory>
        <vcpu placement="static">${toString cfg.resources.vcpus}</vcpu>
        <iothreads>1</iothreads>
        <resource>
          <partition>/machine</partition>
        </resource>
        <cputune>
          <shares>${toString cfg.resources.cpuShares}</shares>
        </cputune>
        <os>
          <type arch="x86_64" machine="${cfg.machine}">hvm</type>
          <loader readonly="yes" secure="yes" type="pflash" format="raw">${secureBootFirmware.firmware}</loader>
          <nvram template="${secureBootFirmware.variablesMs}" templateFormat="raw" format="raw">${nvramPath}</nvram>
          <bootmenu enable="yes" timeout="3000"/>
        </os>
        <features>
          <acpi/>
          <apic/>
          <hyperv mode="custom">
            <relaxed state="on"/>
            <vapic state="on"/>
            <spinlocks state="on" retries="8191"/>
            <vpindex state="on"/>
            <runtime state="on"/>
            <synic state="on"/>
            <stimer state="on">
              <direct state="on"/>
            </stimer>
            <reset state="on"/>
            <frequencies state="on"/>
            <reenlightenment state="on"/>
            <tlbflush state="on"/>
            <ipi state="on"/>
          </hyperv>
          <vmport state="off"/>
          <smm state="on"/>
        </features>
        <cpu mode="host-passthrough" check="none" migratable="off">
          <topology sockets="1" dies="1" cores="${toString cfg.resources.vcpus}" threads="1"/>
          <feature policy="disable" name="svm"/>
        </cpu>
        <clock offset="localtime">
          <timer name="rtc" tickpolicy="catchup"/>
          <timer name="pit" tickpolicy="delay"/>
          <timer name="hpet" present="no"/>
          <timer name="hypervclock" present="yes"/>
        </clock>
        <on_poweroff>destroy</on_poweroff>
        <on_reboot>restart</on_reboot>
        <on_crash>restart</on_crash>
        <pm>
          <suspend-to-mem enabled="no"/>
          <suspend-to-disk enabled="no"/>
        </pm>
        <devices>
          <emulator>${qemuPackage}/bin/qemu-system-x86_64</emulator>
          ${diskDevices}
          <controller type="sata" index="0"/>
          <controller type="scsi" index="0" model="virtio-scsi">
            <driver iothread="1" queues="${toString cfg.resources.vcpus}"/>
          </controller>
          <controller type="usb" index="0" model="qemu-xhci" ports="4"/>
          ${networkDevices}
          <channel type="unix">
            <target type="virtio" name="org.qemu.guest_agent.0"/>
          </channel>
          <input type="tablet" bus="usb"/>
          <input type="keyboard" bus="usb"/>
          <graphics type="spice" autoport="yes">
            <listen type="socket"/>
            <clipboard copypaste="no"/>
            <filetransfer enable="no"/>
            <gl enable="no"/>
          </graphics>
          <video>
            <model type="virtio" heads="1" primary="yes">
              <acceleration accel3d="no"/>
            </model>
          </video>
          <memballoon model="virtio" autodeflate="on">
            <stats period="10"/>
          </memballoon>
          <rng model="virtio">
            <backend model="random">/dev/urandom</backend>
          </rng>
          <tpm model="tpm-crb">
            <backend type="emulator" version="2.0" persistent_state="yes"/>
          </tpm>
          <panic model="hyperv"/>
        </devices>
      </domain>
    '';

  runtimeDomainSource = mkDomainDefinition false;
  installerDomainSource = mkDomainDefinition true;

  validateDomain =
    name: source:
    pkgs.runCommand "validated-${name}-domain.xml" { } ''
      cp ${source} "$out"
      ${getExe' config.virtualisation.libvirtd.package "virt-xml-validate"} "$out" domain
    '';

  runtimeDefinition = validateDomain "${cfg.name}-runtime" runtimeDomainSource;
  installerDefinition = validateDomain "${cfg.name}-installer" installerDomainSource;

  reconcileScript = pkgs.replaceVarsWith {
    name = "libvirt-windows-vm-reconcile";
    src = ./scripts/libvirt-windows-vm-reconcile.sh.in;
    isExecutable = true;
    replacements = {
      autostart = if cfg.autostart then "1" else "0";
      awk = getExe pkgs.gawk;
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

  privilegedControl = pkgs.replaceVarsWith {
    name = "libvirt-windows-vm-control";
    src = ./scripts/libvirt-windows-vm-control.sh.in;
    dir = "libexec";
    isExecutable = true;
    replacements = {
      answerTemplate = escapeShellArg answerTemplate;
      autologonArchive = escapeShellArg autologonArchive;
      autostart = if cfg.autostart then "1" else "0";
      authorizedKeysFile = escapeShellArg authorizedKeysFile;
      awk = getExe pkgs.gawk;
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
      fuseArchive = getExe pkgs.fuse-archive;
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
      mountpoint = getExe' pkgs.util-linux "mountpoint";
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
      rmdir = getExe' pkgs.coreutils "rmdir";
      runtimeDefinition = escapeShellArg runtimeDefinition;
      runtimeDirectory = escapeShellArg runtimeDirectory;
      seedIso = escapeShellArg seedIso;
      seedRenderer = getExe seedRenderer;
      setpriv = getExe' pkgs.util-linux "setpriv";
      sha256sum = getExe' pkgs.coreutils "sha256sum";
      sleep = getExe' pkgs.coreutils "sleep";
      sshKeygen = getExe' pkgs.openssh "ssh-keygen";
      stateDirectory = escapeShellArg stateDirectory;
      storageRoot = escapeShellArg workstation.storage.root;
      umount = getExe' pkgs.util-linux "umount";
      virsh = getExe' config.virtualisation.libvirtd.package "virsh";
      virtioIso = escapeShellArg virtioIso;
      wiminfo = getExe' pkgs.wimlib "wiminfo";
      xmllint = getExe' pkgs.libxml2 "xmllint";
      xorriso = getExe pkgs.xorriso;
    };
  };

  setupWizard = pkgs.replaceVarsWith {
    name = "setup-windows-vm";
    src = ./scripts/setup-windows-vm.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      downloadPage = escapeShellArg cfg.installation.downloadPage;
      guestName = cfg.name;
      imageName = escapeShellArg cfg.installation.imageName;
      isoFileName = escapeShellArg cfg.installation.isoFileName;
      isoSha256 = escapeShellArg normalizedIsoSha256;
      mediaDescription = escapeShellArg cfg.installation.mediaDescription;
      privateDirectory = escapeShellArg privateDirectory;
      release = escapeShellArg cfg.installation.release;
    };
  };

  windowsVmCli = pkgs.replaceVarsWith {
    name = "windows-vm";
    src = ./scripts/windows-vm.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = getExe pkgs.bash;
      cat = getExe' pkgs.coreutils "cat";
      chmod = getExe' pkgs.coreutils "chmod";
      guestName = cfg.name;
      install = getExe' pkgs.coreutils "install";
      isoPath = escapeShellArg isoPath;
      isoSha256 = normalizedIsoSha256;
      isoSha256Path = escapeShellArg isoSha256Path;
      mktemp = getExe' pkgs.coreutils "mktemp";
      mv = getExe' pkgs.coreutils "mv";
      privilegedControl = "${privilegedControl}/libexec/libvirt-windows-vm-control";
      rm = getExe' pkgs.coreutils "rm";
      setupWizard = getExe' setupWizard "setup-windows-vm";
      sha256sum = getExe' pkgs.coreutils "sha256sum";
      sshKeygen = getExe' pkgs.openssh "ssh-keygen";
      sudo = getExe pkgs.sudo;
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
        default = "Pacific Standard Time";
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
        assertion = managementNetwork.mode == "isolated";
        message = "windowsVm.managementNetwork must be host-only.";
      }
      {
        assertion = lib.any (name: workstation.networks.${name}.mode == "nat") cfg.networks;
        message = "windowsVm needs one NAT network for updates and runtime egress.";
      }
      {
        assertion = lib.all (
          name: builtins.hasAttr cfg.name workstation.networks.${name}.reservations
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
      "d /run/libvirt-windows-media 0710 root ${mediaInspectorGroup} -"
      "d ${mediaInspectionDirectory} 0710 root ${mediaInspectorGroup} -"
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
