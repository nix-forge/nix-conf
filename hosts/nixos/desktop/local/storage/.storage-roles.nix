# Fixed desktop mount roles shared by the installed system and Disko.
let
  dataMount = "/srv/data";
  workMount = "${dataMount}/work";
  cacheRoot = "${dataMount}/cache";
  runtimeDirectory = "/run/desktop-storage";
in
{
  inherit
    cacheRoot
    dataMount
    runtimeDirectory
    workMount
    ;
  gamesMount = "/mnt/games";
  vmImagesMount = "/var/lib/libvirt/images";
  homelabMount = "/mnt/homelab";
  scratchRoot = "${workMount}/scratch";
  resticCacheRoot = "${cacheRoot}/restic";
  bulkLockPath = "${runtimeDirectory}/bulk.lock";
}
