{
  home.sessionVariables =
    let
      # You can get the bus ids from the command: lspci | grep -E 'VGA|3D'

      IGPU_BUS_ID = "01:00.0";
      DGPU_BUS_ID = "10:00.0";
    in
    {
      IGPU_CARD = "$(readlink -f /dev/dri/by-path/pci-0000:${IGPU_BUS_ID}-card)";
      DGPU_CARD = "$(readlink -f /dev/dri/by-path/pci-0000:${DGPU_BUS_ID}-card)";
    };
}
