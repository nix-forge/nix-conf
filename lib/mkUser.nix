{
  username,
  name ? "",
  homeModules ? [],
  extraGroups ? [],
  initialPassword ? "password",
  isNormalUser ? true,
}: {
  ${username} = {
    inherit extraGroups initialPassword isNormalUser;
    description = name;
  };
}
