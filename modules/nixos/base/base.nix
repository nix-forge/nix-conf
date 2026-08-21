{ pkgs, ... }: {
  # system.stateVersion is deliberately host-local: it records the NixOS
  # release at installation time and must not be inherited by future hosts.

  # enable dconf
  programs.dconf.enable = true;
  environment.systemPackages = [ pkgs.dconf-editor ];

  services.dbus = {
    enable = true;
    packages = with pkgs; [
      dconf
      gcr
      udisks2
    ];

    # Use the faster dbus-broker instead of the classic dbus-daemon
    implementation = "broker";
  };

  # Enable system-wide wordlist. Some Pandoc filters and other programs
  # depend on wordlist available in system path, and shells do not work.
  environment.wordlist = {
    enable = true;
    lists.WORDLIST = [ "${pkgs.scowl}/share/dict/words.txt" ];
  };

}
