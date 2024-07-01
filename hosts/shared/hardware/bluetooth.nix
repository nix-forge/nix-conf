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

        JustWorksRepairing = "always";
        MultiProfile = "multiple";
      };
    };
  };

  services.blueman.enable = true;
}
