_: {
  programs.rift = {
    enable = true;
    settings = fromTOML (builtins.readFile ./rift/config.toml);
  };
}
