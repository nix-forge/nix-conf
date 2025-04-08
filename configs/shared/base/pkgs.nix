{ pkgs, ... }:
(with pkgs; [
  ##################
  ### ESSENTIALS ###
  ##################

  ### CLI UTILITIES ###
  fastfetch # neofetch but made in c
  wget # simple downloader utility
  curl # network request utility
  p7zip # archive and compression tool
  git # version control
  zip # archive utility
  unzip # archive utility
  bat # cat with wings
  fzf # fuzzy finder
  eza # colored alternative to ls
  ripgrep # grep but rust
  sd # sed but rust
  bc
  tree # directory tree viewer
  rsync # remote sync
  bind.dnsutils # dns utilities
  nixos-install-tools # commands from the NixOS installer
  strace # system call tracer
  unixtools.xxd # hexdump

  ### CODE EDITORS ###
  neovim

  ################
  ### HARDWARE ###
  ################

  ### SYSTEM DEVICES ###
  v4l-utils # proprietary media hardware and encoding
  pciutils # utilities for pci and pcie devices
  lshw # list hardware

  ### STORAGE DEVICE DRIVERS ###
  cryptsetup

  ### STORAGE DEVICE TOOLS ###
  gptfdisk
  e2fsprogs

  ### HARDWARE DIAGNOSTICS ###
  smartmontools # for drive SMART status
  btop # system process monitor
  bottom # not top
  procs # process viewer
  du-dust # du but rust
  usbutils # usb device utilities

  ### VIRTUALIZATION ###
  libguestfs # filesystem driver for vm images
])
