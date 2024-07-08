{
  # Seems to cause issues on my system

  # services.pipewire =
  #   let
  #     default_rate = 192000;
  #   in
  #   {
  #     extraConfig.pipewire = {
  #       # set the the clock rate for audio card
  #       "10-clock-rate" = {
  #         "context.properties" = {
  #           "default.clock.rate" = default_rate;
  #           "default.clock.allowed-rates" = [
  #             44100
  #             48000
  #             88200
  #             96000
  #             176400
  #             192000
  #             384000
  #           ];
  #         };
  #       };
  #     };

  #     # must enable the inputs.nix-gaming.nixosModules.pipewireLowLatency module
  #     lowLatency.rate = default_rate;
  #   };
}
