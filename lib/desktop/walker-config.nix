_: {
  mkWalkerConfig =
    { pkgs, settings }:
    # Walker does not publish a configuration schema. Keep TOML generation here
    # and let Walker own its settings contract rather than duplicating it locally.
    (pkgs.formats.toml { }).generate "walker-config.toml" settings;
}
