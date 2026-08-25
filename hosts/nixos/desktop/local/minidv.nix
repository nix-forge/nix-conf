{ lib, pkgs, ... }:
let
  # Every external command used by the shell sources below resolves through
  # these functions.  The bodies contain absolute Nix-store executables, so
  # the archival commands neither modify nor depend on the caller's PATH.
  minidvRuntime = ''
    basename() { ${lib.getExe' pkgs.coreutils "basename"} "$@"; }
    cat() { ${lib.getExe' pkgs.coreutils "cat"} "$@"; }
    cp() { ${lib.getExe' pkgs.coreutils "cp"} "$@"; }
    date() { ${lib.getExe' pkgs.coreutils "date"} "$@"; }
    df() { ${lib.getExe' pkgs.coreutils "df"} "$@"; }
    dirname() { ${lib.getExe' pkgs.coreutils "dirname"} "$@"; }
    id() { ${lib.getExe' pkgs.coreutils "id"} "$@"; }
    hostname() { ${lib.getExe' pkgs.coreutils "hostname"} "$@"; }
    ls() { ${lib.getExe' pkgs.coreutils "ls"} "$@"; }
    mkdir() { ${lib.getExe' pkgs.coreutils "mkdir"} "$@"; }
    mktemp() { ${lib.getExe' pkgs.coreutils "mktemp"} "$@"; }
    mv() { ${lib.getExe' pkgs.coreutils "mv"} "$@"; }
    realpath() { ${lib.getExe' pkgs.coreutils "realpath"} "$@"; }
    rm() { ${lib.getExe' pkgs.coreutils "rm"} "$@"; }
    sha256sum() { ${lib.getExe' pkgs.coreutils "sha256sum"} "$@"; }
    sleep() { ${lib.getExe' pkgs.coreutils "sleep"} "$@"; }
    tee() { ${lib.getExe' pkgs.coreutils "tee"} "$@"; }
    tail() { ${lib.getExe' pkgs.coreutils "tail"} "$@"; }
    tr() { ${lib.getExe' pkgs.coreutils "tr"} "$@"; }
    uname() { ${lib.getExe' pkgs.coreutils "uname"} "$@"; }
    wc() { ${lib.getExe' pkgs.coreutils "wc"} "$@"; }
    awk() { ${lib.getExe pkgs.gawk} "$@"; }
    grep() { ${lib.getExe pkgs.gnugrep} "$@"; }
    find() { ${lib.getExe pkgs.findutils} "$@"; }
    getfacl() { ${lib.getExe' pkgs.acl "getfacl"} "$@"; }
    dvgrab() { ${lib.getExe pkgs.dvgrab} "$@"; }
    ffmpeg() { ${lib.getExe pkgs.ffmpeg} "$@"; }
    ffprobe() { ${lib.getExe' pkgs.ffmpeg "ffprobe"} "$@"; }
    jq() { ${lib.getExe pkgs.jq} "$@"; }
    flock() { ${lib.getExe' pkgs.util-linux "flock"} "$@"; }
    lspci() { ${lib.getExe pkgs.pciutils} "$@"; }
    lsmod() { ${lib.getExe' pkgs.kmod "lsmod"} "$@"; }
    modinfo() { ${lib.getExe' pkgs.kmod "modinfo"} "$@"; }
    pgrep() { ${lib.getExe' pkgs.procps "pgrep"} "$@"; }
    journalctl() { ${lib.getExe' pkgs.systemd "journalctl"} "$@"; }
    timedatectl() { ${lib.getExe' pkgs.systemd "timedatectl"} "$@"; }
    udevadm() { ${lib.getExe' pkgs.systemd "udevadm"} "$@"; }
  '';

  mkMiniDvApplication =
    {
      name,
      script,
      replacements ? { },
    }:
    (pkgs.replaceVarsWith {
      inherit name;
      src = script;
      dir = "bin";
      isExecutable = true;
      replacements = {
        bash = lib.getExe pkgs.bash;
        inherit minidvRuntime;
      }
      // replacements;
    }).overrideAttrs
      (old: {
        meta = (old.meta or { }) // {
          mainProgram = name;
        };
      });

  minidvVerify = mkMiniDvApplication {
    name = "minidv-verify";
    script = ../minidv/minidv-verify.sh;
  };

  minidvCapture = mkMiniDvApplication {
    name = "minidv-capture";
    script = ../minidv/minidv-capture.sh;
    replacements.minidvVerify = lib.getExe minidvVerify;
  };

  minidvClipManifest = mkMiniDvApplication {
    name = "minidv-clip-manifest";
    script = ../minidv/minidv-clip-manifest.sh;
  };

  minidvTranscode = mkMiniDvApplication {
    name = "minidv-transcode";
    script = ../minidv/minidv-transcode.sh;
    replacements = {
      minidvVerify = lib.getExe minidvVerify;
      minidvClipManifest = lib.getExe minidvClipManifest;
    };
  };

  minidvUpscale = mkMiniDvApplication {
    name = "minidv-upscale";
    script = ../minidv/minidv-upscale.sh;
    replacements = {
      minidvVerify = lib.getExe minidvVerify;
      minidvClipManifest = lib.getExe minidvClipManifest;
    };
  };

  minidvFinalize = mkMiniDvApplication {
    name = "minidv-finalize";
    script = ../minidv/minidv-finalize.sh;
    replacements.minidvVerify = lib.getExe minidvVerify;
  };

  minidvDiagnose = mkMiniDvApplication {
    name = "minidv-diagnose";
    script = ../minidv/minidv-diagnose.sh;
  };

  minidvUdevRules = pkgs.writeTextFile {
    name = "minidv-firewire-udev-rules";
    destination = "/etc/udev/rules.d/70-minidv-firewire.rules";
    text = ''
      SUBSYSTEM=="firewire", KERNEL=="fw[0-9]*", ATTR{is_local}=="1", ATTRS{vendor}=="0x104c", ATTRS{device}=="0x8024", TAG+="uaccess"
    '';
  };
in
{
  # A PCI OHCI FireWire controller carries the standard PCI class alias for
  # firewire_ohci, so udev loads firewire_ohci (and its firewire_core
  # dependency) automatically when the card enumerates.  Do not force-load a
  # bus/DMA driver before there is hardware for it, and do not enable legacy
  # ieee1394, raw1394, dv1394, or video1394 kernel modules.
  environment.systemPackages = [
    # rsync must be installed on the source as well as the Mac destination;
    # it is used for checksum-verifiable copies of the archival master.
    pkgs.rsync
    minidvCapture
    minidvClipManifest
    minidvDiagnose
    minidvFinalize
    minidvTranscode
    minidvUpscale
    minidvVerify
  ];

  # dvgrab opens the local controller character device, which defaults to
  # root-only. This runs before systemd's seat rules so they grant a logind ACL
  # only to the active local session, and only for this TI TSB43AB23
  # controller. It does not change node modes or expose other FireWire devices.
  services.udev.packages = [ minidvUdevRules ];
}
