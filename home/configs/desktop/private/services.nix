{
  config,
  pkgs,
  lib,
  ...
}:
{
  systemd.user.services = {
    rclone_drive_mount =
      let
        rcloneDriveName = "GoogleDriveSchool";
        mountdir = "${config.home.homeDirectory}/cloudstorage/${rcloneDriveName}";
      in
      {
        Unit = {
          Description = "mount rclone drive dirs";
          After = [ "network-online.target" ];
        };
        Install.WantedBy = [ "multi-user.target" ];

        Service = {
          Type = "simple";
          ExecStartPre = "/run/current-system/sw/bin/mkdir -p ${mountdir}";
          ExecStart = ''
            ${lib.getExe pkgs.rclone} mount ${rcloneDriveName}: ${mountdir} \
            --dir-cache-time 48h \
            --vfs-cache-mode full \
            --vfs-cache-max-age 48h \
            --vfs-read-chunk-size 10M \
            --vfs-read-chunk-size-limit 512M \
            --buffer-size 512M
          '';
          ExecStop = "/run/current-system/sw/bin/fusermount -u ${mountdir}";
          Restart = "on-failure";
          RestartSec = "10s";
          Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
        };
      };
  };
}
