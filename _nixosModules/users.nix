{ config, lib, ... }:
{
  options.users = {
    normalUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "List of normal users' usernames.";
    };
    mainUser = lib.mkOption {
      type = lib.types.str;
      default = null;
      description = "Main user's username.";
    };
  };

  config.users = {
    normalUsers =
      let
        nomralUsersSet = lib.filterAttrs (_: user: user.isNormalUser) config.users.users;
      in
      lib.mapAttrsToList (_: user: user.name) nomralUsersSet;
  };
}
