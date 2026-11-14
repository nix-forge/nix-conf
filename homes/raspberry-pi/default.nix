{ modules, ... }: {
  system = "aarch64-linux";
  username = "ianmh";
  homeDirectory = "/home/ianmh";
  uid = 1000;
  standalone = false;
  modules = [
    modules.xdg
    modules.services-workstation-jobs
  ];
}
