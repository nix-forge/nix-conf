{ lib, stdenv }:

stdenv.mkDerivation rec {
  pname = "openocd-esp32-udev-rules";
  version = "master-2024-7-23";

  # Source: https://help.wooting.io/en/article/wootility-configuring-device-access-for-wootility-under-linux-udev-rules-r6lb2o/
  src = [ ./60-openocd.rules ];

  dontUnpack = true;

  installPhase = ''
    install -Dpm644 $src $out/lib/udev/rules.d/60-openocd.rules
  '';

  meta = with lib; {
    homepage = "https://github.com/espressif/openocd-esp32/blob/master/contrib/60-openocd.rules";
    description = "OpenOCD udev rules for ESP32 devices";
    platforms = platforms.linux;
    license = "unknown";
  };
}
