{ inputs, ... }:
{
  imports = [ inputs.nix-gaming.nixosModules.pipewireLowLatency ];

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
          };
        };
      };

      lowLatency = {
        enable = true;
        rate = default_rate;
        quantum = 32;
      };
    };
}
