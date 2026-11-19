{ pkgs, ... }: {
  # Task-owned file watching; no persistent watcher or service is started.
  home.packages = [ pkgs.watchexec ];
}
