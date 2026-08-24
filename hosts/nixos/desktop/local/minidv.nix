{ pkgs, ... }:
let
  commonInputs = with pkgs; [
    acl
    bash
    coreutils
    dvgrab
    ffmpeg
    findutils
    gawk
    gnugrep
    jq
    kmod
    pciutils
    systemd
    util-linux
  ];

  minidvVerify = pkgs.writeShellApplication {
    name = "minidv-verify";
    runtimeInputs = commonInputs;
    text = builtins.readFile ../minidv/minidv-verify.sh;
  };

  minidvCapture = pkgs.writeShellApplication {
    name = "minidv-capture";
    runtimeInputs = commonInputs ++ [ minidvVerify ];
    text = builtins.readFile ../minidv/minidv-capture.sh;
  };

  minidvClipManifest = pkgs.writeShellApplication {
    name = "minidv-clip-manifest";
    runtimeInputs = commonInputs;
    text = builtins.readFile ../minidv/minidv-clip-manifest.sh;
  };

  minidvTranscode = pkgs.writeShellApplication {
    name = "minidv-transcode";
    runtimeInputs = commonInputs ++ [
      minidvVerify
      minidvClipManifest
    ];
    text = builtins.readFile ../minidv/minidv-transcode.sh;
  };

  minidvUpscale = pkgs.writeShellApplication {
    name = "minidv-upscale";
    runtimeInputs = commonInputs ++ [
      minidvVerify
      minidvClipManifest
    ];
    text = builtins.readFile ../minidv/minidv-upscale.sh;
  };

  minidvFinalize = pkgs.writeShellApplication {
    name = "minidv-finalize";
    runtimeInputs = commonInputs ++ [
      minidvVerify
      pkgs.procps
    ];
    text = builtins.readFile ../minidv/minidv-finalize.sh;
  };

  minidvDiagnose = pkgs.writeShellApplication {
    name = "minidv-diagnose";
    runtimeInputs = commonInputs;
    text = builtins.readFile ../minidv/minidv-diagnose.sh;
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
    pkgs.dvgrab
    pkgs.ffmpeg
    pkgs.pciutils
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
