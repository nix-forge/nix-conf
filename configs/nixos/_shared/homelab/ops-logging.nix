{
  profile ? "home-server",
}:
{ ... }:
{
  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=1G
    RuntimeMaxUse=256M
    MaxRetentionSec=14day
    Compress=yes
  '';
}
