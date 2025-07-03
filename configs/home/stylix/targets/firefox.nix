{ config, ... }:
{
  stylix.targets.firefox = {
    enable = true;

    # TODO: rethink if this is the best place to add this option as it becomes a manual process could be better to have a function that takes the profile name
    profileNames = [ config.home.username ];
  };
}
