{ pkgs, ... }: {
  networking.hostName = "nix-public-demo";
  system.stateVersion = "26.05";
  users.users.learner = {
    isNormalUser = true;
    uid = 1000;
  };
  services.getty.autologinUser = "learner";
  systemd.services."getty@tty1" = {
    after = [ "home-manager-learner.service" ];
    requires = [ "home-manager-learner.service" ];
  };
  # Disposable local console login only. This module is for qemu-vm and tests.
  services.openssh.enable = false;
  virtualisation = {
    memorySize = 2048;
    cores = 2;
    graphics = true;
    qemu.options = [ "-vga none -device virtio-gpu-pci" ];
  };
  programs.sway = {
    enable = true;
    extraPackages = [
      pkgs.foot
      pkgs.swaybg
    ];
    wrapperFeatures.gtk = false;
  };
  fonts.packages = [ pkgs.dejavu_fonts ];
  environment.variables = {
    WLR_RENDERER = "pixman";
    SWAYSOCK = "/run/user/1000/public-demo-sway.sock";
  };
  environment.systemPackages = [ pkgs.jq ];
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ]; then
      exec sway
    fi
  '';
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.learner = { lib, ... }: {
      imports = [
        ../../modules/home/dev/git.nix
        ../../modules/home/shells/fzf.nix
        ../../modules/home/shells/integration.nix
        ../../modules/home/shells/starship.nix
      ];
      home = {
        username = "learner";
        homeDirectory = "/home/learner";
        stateVersion = "26.05";
      };
      programs.bash.enable = true;
      # Keep the shared prompt's behavior and use ordinary Unicode for this
      # demo, whose font set deliberately excludes the workstation collection.
      programs.starship.settings = {
        git_branch.symbol = lib.mkForce "git ";
        directory.read_only = lib.mkForce " ro";
        cmd_duration.format = lib.mkForce "[ $duration]($style) ";
        git_status.stashed = lib.mkForce "stash ";
        git_status.conflicted = lib.mkForce "conflict ";
        status = {
          symbol = lib.mkForce "error ";
          not_executable_symbol = lib.mkForce "exec ";
          not_found_symbol = lib.mkForce "missing ";
          sigint_symbol = lib.mkForce "interrupt ";
        };
      };
      xdg.configFile."sway/config".text = ''
        set $mod Mod1
        font pango:DejaVu Sans Mono 11
        output * bg #17212b solid_color
        bindsym $mod+Return exec foot
        bindsym $mod+Shift+q kill
        bindsym $mod+Shift+e exit
        bindsym $mod+1 workspace 1
        bindsym $mod+2 workspace 2
        exec foot --app-id public-demo-terminal
        include /etc/sway/config.d/*
      '';
      xdg.configFile."foot/foot.ini".text = ''
        [main]
        font=DejaVu Sans Mono:size=12
        [colors-dark]
        background=17212b
        foreground=e6edf3
      '';
    };
  };
}
