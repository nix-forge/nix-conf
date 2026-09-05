{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.virtualisation.libvirtWorkstation;

  inherit (lib)
    concatMapStrings
    concatStringsSep
    escapeShellArg
    getExe
    getExe'
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    optionalString
    optionals
    types
    ;

  libvirtUri = "qemu:///system";
  profileMarker = "/etc/libvirt-workstation/profile";
  namePattern = "^[A-Za-z0-9][A-Za-z0-9_.-]*$";
  bridgePattern = "^[A-Za-z0-9][A-Za-z0-9_.-]{0,14}$";
  pciAddressPattern = "^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}[.][0-7]$";
  pciIdPattern = "^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$";
  # The low nibble of the first octet must be 2, 6, a, or e: locally
  # administered and unicast. This avoids colliding with real NIC OUIs.
  macAddressPattern = "^[0-9a-fA-F][26aAeE](:[0-9a-fA-F]{2}){5}$";
  mutablePathPattern = "^/[A-Za-z0-9._+/-]+$";
  ipv4Octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
  privateIpv4PrefixPattern = "^(10[.]${ipv4Octet}[.]${ipv4Octet}|172[.](1[6-9]|2[0-9]|3[01])[.]${ipv4Octet}|192[.]168[.]${ipv4Octet})$";

  reservationModule = types.submodule {
    options = {
      macAddress = mkOption {
        type = types.strMatching macAddressPattern;
        example = "52:54:00:12:30:10";
        description = "Stable, locally administered guest interface MAC address.";
      };

      address = mkOption {
        type = types.ints.between 2 254;
        example = 10;
        description = "Final octet of this guest's fixed address on the network.";
      };
    };
  };

  networkModule = types.submodule (
    { name, ... }: {
      options = {
        mode = mkOption {
          type = types.enum [
            "isolated"
            "nat"
          ];
          default = "nat";
          description = "Whether this network is host-only or has outbound NAT.";
        };

        bridge = mkOption {
          type = types.strMatching bridgePattern;
          default = "virbr-${name}";
          description = "Linux bridge name. Linux interface names are limited to 15 characters.";
        };

        ipv4Prefix = mkOption {
          type = types.strMatching privateIpv4PrefixPattern;
          example = "192.168.122";
          description = "First three octets of this RFC 1918 private /24 subnet.";
        };

        domain = mkOption {
          type = types.strMatching namePattern;
          default = "${name}.vm.internal";
          description = "Local DNS domain advertised by libvirt's DNS service.";
        };

        dhcp = {
          start = mkOption {
            type = types.ints.between 2 254;
            default = 100;
            description = "First dynamic DHCP address in the /24.";
          };

          end = mkOption {
            type = types.ints.between 2 254;
            default = 199;
            description = "Last dynamic DHCP address in the /24.";
          };
        };

        reservations = mkOption {
          type = types.attrsOf reservationModule;
          default = { };
          example.linux-dev = {
            macAddress = "52:54:00:12:30:10";
            address = 10;
          };
          description = "Fixed DHCP leases keyed by guest DNS name.";
        };

        isolateGuests = mkOption {
          type = types.bool;
          default = true;
          description = "Prevent guests on this libvirt network from directly talking to one another.";
        };

        hostTcpPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          example = [ 22 ];
          description = "Additional TCP ports guests on this network may reach on the host.";
        };

        hostUdpPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          description = "Additional UDP ports guests on this network may reach on the host.";
        };

        allowHostPing = mkOption {
          type = types.bool;
          default = true;
          description = "Allow IPv4 ICMP echo requests from this network to the host bridge address.";
        };

        allowPrivateEgress = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Allow a NAT guest to initiate connections to private, shared,
            link-local, multicast, and reserved IPv4 destinations. Public
            internet egress remains available when this is false.
          '';
        };
      };
    }
  );

  guestModule = types.submodule {
    options = {
      autostart = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Start this domain with libvirtd. Keep this false on an interactive
          workstation; enabling it is appropriate only after unattended boot,
          shutdown, update, and recovery tests pass.
        '';
      };

      inhibitSleep = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Hold a systemd-logind sleep inhibitor while this domain is active.
          Use this for guests whose network availability must not be silently
          interrupted by workstation idle-suspend policy.
        '';
      };

      sshHost = mkOption {
        type = types.nullOr (types.strMatching namePattern);
        default = null;
        example = "linux-dev";
        description = ''
          Existing OpenSSH alias used by `vm ssh`. Keep this null until the
          guest has a unique key and a pinned host-key entry.
        '';
      };

      exclusiveGroup = mkOption {
        type = types.nullOr (types.strMatching namePattern);
        default = null;
        example = "heavy";
        description = ''
          Optional local scheduling group. The `vm start` command refuses to
          start a guest while another allowlisted guest in this group is active.
        '';
      };

      requiredProfile = mkOption {
        type = types.nullOr (types.strMatching namePattern);
        default = null;
        example = "windows-vfio";
        description = ''
          Boot profile required to start this guest. Libvirt's QEMU hook also
          enforces this guard when a graphical manager bypasses the `vm` CLI.
        '';
      };
    };
  };

  vfioDeviceModule = types.submodule {
    options = {
      pciAddress = mkOption {
        type = types.strMatching pciAddressPattern;
        example = "0000:01:00.0";
        description = "Full PCI address of this function.";
      };

      vendorDeviceId = mkOption {
        type = types.strMatching pciIdPattern;
        example = "10de:2786";
        description = "Lower- or upper-case PCI vendor and device ID used by vfio-pci.";
      };

      iommuGroup = mkOption {
        type = types.ints.unsigned;
        example = 12;
        description = "Expected IOMMU group, rechecked by `vm doctor` before use.";
      };
    };
  };

  qemuPackage = if cfg.emulateAarch64 then pkgs.qemu else pkgs.qemu_kvm;
  networkNames = builtins.attrNames cfg.networks;
  guestNames = builtins.attrNames cfg.guests;
  vfioDeviceNames = builtins.attrNames cfg.vfio.devices;
  normalizedVfioIds = lib.unique (
    map (device: lib.toLower device.vendorDeviceId) (builtins.attrValues cfg.vfio.devices)
  );
  vfioIdArgument = concatStringsSep "," normalizedVfioIds;
  vfioAddresses = map (device: lib.toLower device.pciAddress) (builtins.attrValues cfg.vfio.devices);

  rawNetworkDefinitions = lib.mapAttrs (
    name: network:
    pkgs.writeText "libvirt-${name}-network.xml" ''
      <network>
        <name>${name}</name>
        <metadata>
          <description xmlns="https://ianmh.dev/libvirt/network/1">NixOS-managed development network</description>
        </metadata>
        ${optionalString (network.mode == "nat") ''
          <forward mode="nat">
            <nat>
              <port start="1024" end="65535"/>
            </nat>
          </forward>
        ''}
        <bridge name="${network.bridge}" stp="on" delay="0" macTableManager="libvirt"/>
        ${optionalString network.isolateGuests ''<port isolated="yes"/>''}
        <domain name="${network.domain}" localOnly="yes"/>
        <dns enable="yes"/>
        <ip address="${network.ipv4Prefix}.1" netmask="255.255.255.0">
          <dhcp>
            <range start="${network.ipv4Prefix}.${toString network.dhcp.start}" end="${network.ipv4Prefix}.${toString network.dhcp.end}"/>
            ${concatMapStrings (
              reservationName:
              let
                reservation = network.reservations.${reservationName};
              in
              ''<host mac="${lib.toLower reservation.macAddress}" name="${reservationName}" ip="${network.ipv4Prefix}.${toString reservation.address}"/>''
            ) (builtins.attrNames network.reservations)}
          </dhcp>
        </ip>
      </network>
    ''
  ) cfg.networks;

  validateLibvirtXml =
    kind: name: source:
    pkgs.runCommand "validated-libvirt-${name}-${kind}.xml" { } ''
      cp ${source} "$out"
      ${getExe' config.virtualisation.libvirtd.package "virt-xml-validate"} "$out" ${kind}
    '';

  networkDefinitions = lib.mapAttrs (
    name: source: validateLibvirtXml "network" name source
  ) rawNetworkDefinitions;

  rawStoragePoolDefinition = pkgs.writeText "libvirt-${cfg.storage.poolName}-storage-pool.xml" ''
    <pool type="dir">
      <name>${cfg.storage.poolName}</name>
      <target>
        <path>${cfg.storage.root}</path>
        <permissions>
          <mode>0710</mode>
          <owner>0</owner>
          <group>${toString config.ids.gids.qemu-libvirtd}</group>
        </permissions>
      </target>
    </pool>
  '';
  storagePoolDefinition =
    validateLibvirtXml "storagepool" cfg.storage.poolName
      rawStoragePoolDefinition;

  networkManifest = pkgs.writeText "libvirt-workstation-networks.tsv" (
    concatMapStrings (
      name:
      let
        network = cfg.networks.${name};
      in
      "${name}\t${network.bridge}\t${network.ipv4Prefix}.0/24\t${networkDefinitions.${name}}\n"
    ) networkNames
  );

  guestManifest = pkgs.writeText "libvirt-workstation-guests.tsv" (
    concatMapStrings (
      name:
      let
        guest = cfg.guests.${name};
        valueOrDash = value: if value == null then "-" else value;
      in
      "${name}\t${valueOrDash guest.sshHost}\t${valueOrDash guest.exclusiveGroup}\t${valueOrDash guest.requiredProfile}\t${
        if guest.autostart then "1" else "0"
      }\t${if guest.inhibitSleep then "1" else "0"}\n"
    ) guestNames
  );

  vfioDeviceManifest = pkgs.writeText "libvirt-workstation-vfio-devices.tsv" (
    concatMapStrings (
      name:
      let
        device = cfg.vfio.devices.${name};
      in
      "${name}\t${lib.toLower device.pciAddress}\t${lib.toLower device.vendorDeviceId}\t${toString device.iommuGroup}\n"
    ) vfioDeviceNames
  );

  workstationSetup = pkgs.replaceVarsWith {
    name = "libvirt-workstation-setup";
    src = ./scripts/libvirt-workstation-setup.sh.in;
    isExecutable = true;
    replacements = {
      bash = getExe pkgs.bash;
      grep = getExe pkgs.gnugrep;
      guestManifest = escapeShellArg guestManifest;
      libvirtUri = escapeShellArg libvirtUri;
      mktemp = getExe' pkgs.coreutils "mktemp";
      networkManifest = escapeShellArg networkManifest;
      perl = getExe pkgs.perl;
      poolDefinition = escapeShellArg storagePoolDefinition;
      poolName = escapeShellArg cfg.storage.poolName;
      poolPath = escapeShellArg cfg.storage.root;
      rm = getExe' pkgs.coreutils "rm";
      virsh = getExe' config.virtualisation.libvirtd.package "virsh";
      xmllint = getExe' pkgs.libxml2 "xmllint";
    };
  };

  profileGuard = pkgs.replaceVarsWith {
    name = "libvirt-workstation-profile-guard";
    src = ./scripts/libvirt-workstation-profile-guard.sh.in;
    isExecutable = true;
    replacements = {
      bash = getExe pkgs.bash;
      basename = getExe' pkgs.coreutils "basename";
      guestManifest = escapeShellArg guestManifest;
      profileMarker = escapeShellArg profileMarker;
      readlink = getExe' pkgs.coreutils "readlink";
      vfioDeviceManifest = escapeShellArg vfioDeviceManifest;
      vfioProfile = escapeShellArg cfg.vfio.specialisationName;
    };
  };

  sleepInhibitorHook = pkgs.replaceVarsWith {
    name = "libvirt-workstation-sleep-inhibitor-hook";
    src = ./scripts/libvirt-workstation-sleep-inhibitor-hook.sh.in;
    isExecutable = true;
    replacements = {
      bash = getExe pkgs.bash;
      guestManifest = escapeShellArg guestManifest;
      systemctl = getExe' pkgs.systemd "systemctl";
      systemdEscape = getExe' pkgs.systemd "systemd-escape";
    };
  };

  sleepInhibitorReady = pkgs.writeShellScript "libvirt-workstation-sleep-inhibitor-ready" ''
    set -euo pipefail
    # systemd-inhibit invokes this only after logind grants the inhibitor.
    ${getExe' pkgs.systemd "systemd-notify"} --ready
    exec ${getExe' pkgs.coreutils "sleep"} infinity
  '';

  privilegedControl = pkgs.replaceVarsWith {
    name = "libvirt-workstation-control";
    src = ./scripts/libvirt-workstation-control.sh.in;
    dir = "libexec";
    isExecutable = true;
    replacements = {
      awk = getExe pkgs.gawk;
      bash = getExe pkgs.bash;
      basename = getExe' pkgs.coreutils "basename";
      emulateAarch64 = if cfg.emulateAarch64 then "1" else "0";
      findmnt = getExe' pkgs.util-linux "findmnt";
      grep = getExe pkgs.gnugrep;
      guestManifest = escapeShellArg guestManifest;
      iommuEnabled = if cfg.vfio.enable then "1" else "0";
      ip = getExe' pkgs.iproute2 "ip";
      libvirtUri = escapeShellArg libvirtUri;
      lsattr = getExe' pkgs.e2fsprogs "lsattr";
      lspci = getExe pkgs.pciutils;
      networkManifest = escapeShellArg networkManifest;
      poolName = escapeShellArg cfg.storage.poolName;
      poolPath = escapeShellArg cfg.storage.root;
      profileMarker = escapeShellArg profileMarker;
      ps = getExe' pkgs.procps "ps";
      qemuAarch64 = "${qemuPackage}/bin/qemu-system-aarch64";
      readlink = getExe' pkgs.coreutils "readlink";
      ss = getExe' pkgs.iproute2 "ss";
      storageNocow = if cfg.storage.nocow then "1" else "0";
      systemctl = getExe' pkgs.systemd "systemctl";
      systemdEscape = getExe' pkgs.systemd "systemd-escape";
      vfioDeviceManifest = escapeShellArg vfioDeviceManifest;
      vfioEnabled = if cfg.vfio.enable then "1" else "0";
      vfioProfile = escapeShellArg cfg.vfio.specialisationName;
      virsh = getExe' config.virtualisation.libvirtd.package "virsh";
      virtHostValidate = getExe' config.virtualisation.libvirtd.package "virt-host-validate";
      xmllint = getExe' pkgs.libxml2 "xmllint";
    };
  };

  vmCli = pkgs.replaceVarsWith {
    name = "vm";
    src = ./scripts/vm.sh.in;
    dir = "bin";
    isExecutable = true;
    replacements = {
      bash = getExe pkgs.bash;
      guestManifest = escapeShellArg guestManifest;
      privilegedControl = "${privilegedControl}/libexec/libvirt-workstation-control";
      ssh = getExe pkgs.openssh;
      sudo = getExe pkgs.sudo;
      virtManager = getExe pkgs.virt-manager;
    };
  };

  hostAudit = pkgs.writeShellApplication {
    name = "virt-host-audit";
    text = ''
      exec ${getExe' vmCli "vm"} doctor "$@"
    '';
  };

  networkBridges = map (name: cfg.networks.${name}.bridge) networkNames;
  networkPrefixes = map (name: cfg.networks.${name}.ipv4Prefix) networkNames;
  allReservations = lib.concatMap (
    name:
    map (reservationName: {
      inherit name reservationName;
      inherit (cfg.networks.${name}.reservations.${reservationName}) address macAddress;
    }) (builtins.attrNames cfg.networks.${name}.reservations)
  ) networkNames;
  allReservationMacs = map (reservation: lib.toLower reservation.macAddress) allReservations;
  currentProfileRequirements = map (name: cfg.guests.${name}.requiredProfile) guestNames;
  firewallRules = concatMapStrings (
    name:
    let
      network = cfg.networks.${name};
      tcpPorts = [ 53 ] ++ network.hostTcpPorts;
      udpPorts = [
        53
        67
      ]
      ++ network.hostUdpPorts;
      portSet = ports: concatStringsSep ", " (map toString (lib.unique ports));
    in
    ''
      iifname "${network.bridge}" tcp dport { ${portSet tcpPorts} } accept comment "allow reviewed ${name} guest-to-host TCP"
      iifname "${network.bridge}" udp dport { ${portSet udpPorts} } accept comment "allow reviewed ${name} guest-to-host UDP"
      ${optionalString network.allowHostPing ''iifname "${network.bridge}" icmp type echo-request accept comment "allow ${name} guest diagnostics"''}
      iifname "${network.bridge}" drop comment "isolate ${name} guests from host services"
    ''
  ) networkNames;
  restrictedIpv4Destinations = concatStringsSep ", " [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.0.0.0/24"
    "192.0.2.0/24"
    "192.88.99.0/24"
    "192.168.0.0/16"
    "198.18.0.0/15"
    "198.51.100.0/24"
    "203.0.113.0/24"
    "224.0.0.0/4"
    "240.0.0.0/4"
  ];
  privateEgressRules = concatMapStrings (
    name:
    let
      network = cfg.networks.${name};
    in
    optionalString (network.mode == "nat" && !network.allowPrivateEgress) ''
      iifname "${network.bridge}" ip daddr { ${restrictedIpv4Destinations} } counter drop comment "block ${name} guest egress to non-public IPv4"
    ''
  ) networkNames;
  hasSunshineOption = lib.hasAttrByPath [ "services" "sunshine" "enable" ] options;
in
{
  imports = [ ./windows-vm.nix ];

  options.virtualisation.libvirtWorkstation = {
    enable = mkEnableOption ''
      a hardened libvirt/QEMU development workstation with declarative private
      networks, managed storage, a narrow VM lifecycle CLI, and virt-manager
    '';

    operators = mkOption {
      type = types.listOf types.nonEmptyStr;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Existing local accounts allowed to use the allowlisted `vm` lifecycle
        command and write installation media. This does not grant membership in
        libvirtd, kvm, disk, or a VFIO group.
      '';
    };

    emulateAarch64 = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install full-system QEMU so this host can emulate trusted AArch64
        guests. Cross-ISA TCG is slow and is not a supported security boundary.
      '';
    };

    networks = mkOption {
      type = types.attrsOf networkModule;
      default = {
        development = {
          mode = "nat";
          bridge = "virbr-dev";
          ipv4Prefix = "192.168.122";
          domain = "vm.internal";
        };
      };
      description = ''
        Private libvirt networks reconciled at boot. Existing networks are
        updated persistently but never restarted while guests may be using them.
      '';
    };

    storage = {
      poolName = mkOption {
        type = types.strMatching namePattern;
        default = "default";
        description = "Name of the managed directory storage pool.";
      };

      root = mkOption {
        type = types.strMatching mutablePathPattern;
        default = "/var/lib/libvirt/images";
        description = "Absolute directory containing mutable guest disks.";
      };

      installationMedia = mkOption {
        type = types.strMatching mutablePathPattern;
        default = "/var/lib/libvirt/boot";
        description = "Absolute directory where operators may stage trusted ISO images.";
      };

      nocow = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Set the NOCOW directory attribute for newly created images. Enable
          this only when the storage filesystem supports it, such as Btrfs.
        '';
      };
    };

    guests = mkOption {
      type = types.attrsOf guestModule;
      default = { };
      example = {
        linux-dev = {
          sshHost = "linux-dev";
          exclusiveGroup = "heavy";
        };
      };
      description = ''
        Existing libvirt domain names exposed to the routine `vm` command.
        This is a lifecycle allowlist, not domain XML or mutable disk state.
      '';
    };

    usbRedirection.enable = mkEnableOption ''
      SPICE USB redirection. It installs a privileged helper that lets VM
      operators access arbitrary USB devices, so it remains opt-in
    '';

    vfio = {
      enable = mkEnableOption ''
        a reboot-selected VFIO boot specialization for explicitly declared PCI functions
      '';

      specialisationName = mkOption {
        type = types.strMatching namePattern;
        default = "windows-vfio";
        description = "Boot specialization name and runtime profile marker.";
      };

      devices = mkOption {
        type = types.attrsOf vfioDeviceModule;
        default = { };
        description = ''
          Every PCI function in each passed IOMMU group. These host-local facts
          are checked at runtime before a guarded guest starts.
        '';
      };

      hostVideoDrivers = mkOption {
        type = types.listOf types.nonEmptyStr;
        default = [ ];
        example = [ "amdgpu" ];
        description = "Display drivers retained by the NixOS host in the VFIO specialization.";
      };

      hostInitrdModules = mkOption {
        type = types.listOf types.nonEmptyStr;
        default = [ ];
        example = [ "amdgpu" ];
        description = "Host display modules loaded before VFIO in the specialization initrd.";
      };

      blacklistedModules = mkOption {
        type = types.listOf types.nonEmptyStr;
        default = [ ];
        example = [
          "nouveau"
          "nvidia"
          "nvidia_drm"
          "nvidia_modeset"
          "nvidia_uvm"
        ];
        description = "Host drivers prevented from claiming the passed device functions.";
      };

      disableSunshine = mkOption {
        type = types.bool;
        default = true;
        description = "Disable the NixOS Sunshine service in the VFIO specialization when present.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.isLinux;
          message = "virtualisation.libvirtWorkstation is implemented only for Linux hosts.";
        }
        {
          assertion = cfg.operators != [ ];
          message = "virtualisation.libvirtWorkstation.operators must name at least one local account.";
        }
        {
          assertion = lib.all (user: builtins.hasAttr user config.users.users) cfg.operators;
          message = "Every libvirt workstation operator must name an existing local account.";
        }
        {
          assertion = cfg.networks != { };
          message = "virtualisation.libvirtWorkstation.networks must not be empty.";
        }
        {
          assertion = lib.all (name: builtins.match namePattern name != null) networkNames;
          message = "Libvirt workstation network names may contain only letters, digits, dots, underscores, and dashes.";
        }
        {
          assertion = lib.length networkBridges == lib.length (lib.unique networkBridges);
          message = "Every libvirt workstation network needs a unique bridge name.";
        }
        {
          assertion = lib.length networkPrefixes == lib.length (lib.unique networkPrefixes);
          message = "Every libvirt workstation network needs a unique IPv4 /24.";
        }
        {
          assertion = lib.all (
            name: cfg.networks.${name}.dhcp.start <= cfg.networks.${name}.dhcp.end
          ) networkNames;
          message = "Each libvirt workstation DHCP range must start at or before its end address.";
        }
        {
          assertion = lib.all (
            reservation: builtins.match namePattern reservation.reservationName != null
          ) allReservations;
          message = "DHCP reservation names may contain only letters, digits, dots, underscores, and dashes.";
        }
        {
          assertion = lib.all (
            name:
            let
              addresses = map (reservation: reservation.address) (
                builtins.attrValues cfg.networks.${name}.reservations
              );
            in
            lib.length addresses == lib.length (lib.unique addresses)
          ) networkNames;
          message = "Fixed DHCP reservation addresses must be unique within each network.";
        }
        {
          assertion = lib.all (
            reservation:
            let
              network = cfg.networks.${reservation.name};
            in
            reservation.address < network.dhcp.start || reservation.address > network.dhcp.end
          ) allReservations;
          message = "Fixed DHCP reservations must remain outside their network's dynamic range.";
        }
        {
          assertion = lib.length allReservationMacs == lib.length (lib.unique allReservationMacs);
          message = "Every declared guest network interface needs a globally unique MAC address.";
        }
        {
          assertion = lib.all (name: builtins.match namePattern name != null) guestNames;
          message = "Managed guest names may contain only letters, digits, dots, underscores, and dashes.";
        }
        {
          assertion = lib.all (
            profile: profile == null || profile == "default" || profile == cfg.vfio.specialisationName
          ) currentProfileRequirements;
          message = "A guest requiredProfile must be `default`, null, or the configured VFIO specialization.";
        }
        {
          assertion =
            !lib.elem cfg.vfio.specialisationName [
              "default"
              "configuration"
            ];
          message = "The VFIO specialization name must not be `default` or `configuration`.";
        }
        {
          assertion =
            lib.all
              (
                path:
                lib.hasPrefix "/" path
                && path != "/"
                && !lib.hasSuffix "/" path
                && !lib.hasInfix "//" path
                && !lib.elem "." (lib.splitString "/" path)
                && !lib.elem ".." (lib.splitString "/" path)
                && !lib.hasPrefix "/nix/store" path
                && path != "/tmp"
                && !lib.hasPrefix "/tmp/" path
              )
              [
                cfg.storage.root
                cfg.storage.installationMedia
              ];
          message = "Libvirt mutable storage paths must be absolute and outside /nix/store and /tmp.";
        }
        {
          assertion = cfg.storage.root != cfg.storage.installationMedia;
          message = "Guest disks and installation media must use distinct directories.";
        }
        {
          assertion = config.networking.nftables.enable;
          message = "virtualisation.libvirtWorkstation requires nftables for libvirt's firewall.";
        }
        {
          assertion = !config.virtualisation.incus.enable;
          message = "Do not run Incus and the libvirt workstation on the same desktop; select one QEMU manager.";
        }
        {
          assertion = lib.all (
            bridge: !lib.elem bridge config.networking.firewall.trustedInterfaces
          ) networkBridges;
          message = "Do not place a libvirt workstation bridge in networking.firewall.trustedInterfaces.";
        }
        {
          assertion = !cfg.vfio.enable || cfg.vfio.devices != { };
          message = "VFIO requires at least one explicitly declared PCI function.";
        }
        {
          assertion = !cfg.vfio.enable || cfg.vfio.hostVideoDrivers != [ ];
          message = "VFIO requires an explicit hostVideoDrivers recovery path.";
        }
        {
          assertion = !cfg.vfio.enable || cfg.vfio.hostInitrdModules != [ ];
          message = "VFIO requires an explicit hostInitrdModules recovery path.";
        }
        {
          assertion = lib.length vfioAddresses == lib.length (lib.unique vfioAddresses);
          message = "VFIO PCI addresses must be unique.";
        }
        {
          assertion =
            cfg.vfio.enable
            || lib.all (profile: profile != cfg.vfio.specialisationName) currentProfileRequirements;
          message = "A guest cannot require the VFIO profile while that specialization is disabled.";
        }
      ];

      virtualisation = {
        libvirtd = {
          enable = true;
          allowedBridges = [ ];
          firewallBackend = "nftables";
          onBoot = "ignore";
          onShutdown = "shutdown";
          parallelShutdown = 2;
          shutdownTimeout = 180;
          sshProxy = false;

          qemu = {
            package = qemuPackage;
            runAsRoot = false;
            swtpm.enable = true;
            vhostUserPackages = [ pkgs.virtiofsd ];

            # NixOS currently disables QEMU mount namespaces because store
            # paths and device helpers need host-specific validation. Keep
            # that limitation explicit while still requiring seccomp.
            verbatimConfig = ''
              namespaces = []
              seccomp_sandbox = 1
            '';
          };

          hooks.qemu = {
            "10-workstation-profile-guard" = profileGuard;
            "20-workstation-sleep-inhibitor" = sleepInhibitorHook;
          };

          # Resolve domain names from libvirt's own guest records without
          # enabling multicast discovery on the physical network.
          nss.enableGuest = true;
        };

        spiceUSBRedirection.enable = cfg.usbRedirection.enable;
      };

      programs.virt-manager.enable = true;

      # Libvirt owns forwarding and NAT. The host firewall allows only the
      # network's DHCP/DNS service, optional diagnostics, and ports named by
      # this module before rejecting all other guest-to-host traffic.
      networking.firewall.extraInputRules = lib.mkBefore firewallRules;

      # This early forward hook only issues terminal drop verdicts. Traffic
      # that passes it continues into libvirt's own forwarding/NAT chains.
      networking.nftables.tables.libvirt-workstation-egress = mkIf (privateEgressRules != "") {
        family = "inet";
        content = ''
          chain restrict-forward {
            type filter hook forward priority -10; policy accept;
            ${privateEgressRules}
          }
        '';
      };

      users = {
        groups.libvirt-media = { };
        users = {
          qemu-libvirtd.extraGroups = [ "libvirt-media" ];
        }
        // lib.genAttrs cfg.operators (_: {
          # This group can stage ISO files but cannot open the libvirt
          # management socket or host devices.
          extraGroups = [ "libvirt-media" ];
        });
      };

      environment = {
        sessionVariables.LIBVIRT_DEFAULT_URI = libvirtUri;

        etc = {
          "libvirt-workstation/profile".text = "default\n";

          # The package exposes an unpacked driver tree. Keep its original
          # ISO at a stable path for the Windows installer.
          "libvirt/virtio-win.iso".source = pkgs.virtio-win.src;
        };

        systemPackages = [
          hostAudit
          vmCli
          pkgs.guestfs-tools
          pkgs.libosinfo
          pkgs.osinfo-db
          pkgs.virtnbdbackup
          pkgs.virt-viewer
        ]
        ++ optionals cfg.vfio.enable [ pkgs.looking-glass-client ];
      };

      # Operators may invoke only this immutable, allowlist-validating
      # helper without a password. It does not accept XML, paths, shell code,
      # force-stop, delete, or arbitrary virsh subcommands.
      security.sudo.extraRules = map (operator: {
        users = [ operator ];
        commands = [
          {
            command = "${privilegedControl}/libexec/libvirt-workstation-control";
            options = [
              "NOPASSWD"
              "NOSETENV"
            ];
          }
        ];
      }) cfg.operators;

      systemd = {
        tmpfiles.rules = [
          "d ${cfg.storage.root} 0710 root qemu-libvirtd -"
          "d ${cfg.storage.installationMedia} 2770 root libvirt-media -"
        ]
        ++ optionals cfg.storage.nocow [
          # The directory attribute affects files created after it is set. The
          # audit warns about pre-existing images that remain copy-on-write.
          "h ${cfg.storage.root} - - - - +C"
        ];

        services.libvirt-workstation-setup = {
          description = "Reconcile development libvirt networks and storage";
          wantedBy = [ "multi-user.target" ];
          after = [ "libvirtd.service" ];
          before = [ "libvirt-guests.service" ];
          requires = [ "libvirtd.service" ];
          restartTriggers = [
            networkManifest
            storagePoolDefinition
            guestManifest
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = workstationSetup;
            RemainAfterExit = true;
            UMask = "0077";
          };
        };

        services."libvirt-workstation-sleep-inhibit@" = {
          description = "Prevent host sleep while managed libvirt guest %i is running";
          serviceConfig = {
            Type = "notify";
            NotifyAccess = "all";
            TimeoutStartSec = 15;
            ExecStart = "${getExe' pkgs.systemd "systemd-inhibit"} --what=sleep --who=libvirt-guest-%i --why=managed-guest-is-running --mode=block ${sleepInhibitorReady}";
            Restart = "always";
            RestartSec = 5;
            CapabilityBoundingSet = "";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
            UMask = "0077";
          };
        };
      };
    }

    (mkIf cfg.vfio.enable {
      specialisation.${cfg.vfio.specialisationName}.configuration = mkMerge [
        {
          system.nixos.tags = [ cfg.vfio.specialisationName ];
          environment.etc."libvirt-workstation/profile".text = lib.mkForce "${cfg.vfio.specialisationName}\n";

          services.xserver.videoDrivers = lib.mkForce cfg.vfio.hostVideoDrivers;

          # Load the recovery display first, then bind the complete selected
          # groups before a host graphics or audio driver can claim them.
          boot = {
            initrd.kernelModules = lib.mkBefore (
              cfg.vfio.hostInitrdModules
              ++ [
                "vfio"
                "vfio_iommu_type1"
                "vfio_pci"
              ]
            );
            kernelModules = [
              "vfio"
              "vfio_iommu_type1"
              "vfio_pci"
            ];
            blacklistedKernelModules = cfg.vfio.blacklistedModules;
            kernelParams = [ "vfio-pci.ids=${vfioIdArgument}" ];
          };
        }

        (optionalAttrs (cfg.vfio.disableSunshine && hasSunshineOption) {
          services.sunshine.enable = lib.mkForce false;
        })
      ];
    })
  ]);
}
