{
  programs.atuin = {
    enable = true;

    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      update_check = false;
      search_mode = "fuzzy";
      filter_mode = "global";
      style = "auto";
      show_preview = true;
    };
  };
}
