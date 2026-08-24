{
  boot.kernelParams = [ "btusb" ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    disabledPlugins = [ "sap" ];

    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        ControllerMode = "dual";

        # Require local confirmation before a previously paired Bluetooth
        # device can silently replace its pairing key.
        JustWorksRepairing = "confirm";
        MultiProfile = "multiple";
      };
    };
  };

  services.blueman.enable = true;
}
