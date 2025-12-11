{ inputs, ... }:
{
  imports = [ inputs.nix-gaming-custom.nixosModules.pipewireLowLatency ];

  services.pipewire =
    let
      default_rate = 48000;
    in
    {
      extraConfig.pipewire = {
        # set the the clock rate for audio card
        "10-clock-rate" = {
          "context.properties" = {
            "default.clock.rate" = default_rate;
            "default.clock.allowed-rates" = [
              44100
              48000
            ];
          };
        };
      };

      lowLatency = {
        enable = true;
        rate = default_rate;
        quantum = 128;
        alsa = {
          enable = true;
          format = "S24_3LE";
          devicePattern = "~alsa_output.usb-Generic_USB_Audio-00.*";
          periodSize = 128;
        };
      };
    };
}
