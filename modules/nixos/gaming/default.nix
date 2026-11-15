{
  # Hardware, account, and network policy for remote play belongs to each
  # host's local/ tree rather than this reusable gaming selection.
  imports = [
    ./steam.nix
    ./gamemode.nix
    ./gamescope.nix
  ];
}
