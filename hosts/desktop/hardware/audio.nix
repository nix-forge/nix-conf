{ inputs, ... }:
{
  imports = [ inputs.nix-gaming.nixosModules.pipewireLowLatency ];

  services.pipewire =
    let
      default_rate = 96000;
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
              96000
              192000 # noticed some loss of audio quality ocassionally
            ];
          };
        };
      };

      lowLatency = {
        enable = true;
        rate = default_rate;
      };
    };
}
