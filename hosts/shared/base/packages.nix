{
  pkgs,
  config,
  lib,
  ...
}:
{
  # remove the default packages from the system closure
  # It is important the rest of the packages are not removed
  # as they are required to run the system at a base state.
  environment.defaultPackages = lib.mkForce [ ];

  # Packages which are appropriate for a typical Linux system.
  # There should be **no GUI programs** in this list.
  environment.systemPackages = with pkgs; [
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

    ### CODE EDITORS ###
    neovim

    ################
    ### HARDWARE ###
    ################

    ### SYSTEM DEVICES ###
    config.boot.kernelPackages.cpupower
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
    bandwhich # network monitor

    ### VIRTUALIZATION ###
    libguestfs # filesystem driver for vm images
  ];
}
