{
  render = { palette }: {
    "$schema" = "vscode://schemas/color-theme";
    name = "Carbon Neon OLED";
    include = "./carbon-neon-color-theme.json";
    colors = {
      "widget.shadow" = "#${palette.surface}CC";
      "titleBar.activeBackground" = "#${palette.surface}";
      "titleBar.inactiveBackground" = "#${palette.surface}";
      "activityBar.background" = "#${palette.surface}";
      "activityBarTop.background" = "#${palette.surfaceChrome}";
      "sideBar.background" = "#${palette.surface}";
      "editorGroupHeader.tabsBackground" = "#${palette.surfaceChrome}";
      "tab.activeBackground" = "#${palette.surface}";
      "tab.inactiveBackground" = "#${palette.surfaceChrome}";
      "editor.background" = "#${palette.surface}";
      "editorGutter.background" = "#${palette.surface}";
      "statusBar.background" = "#${palette.surface}";
      "statusBar.noFolderBackground" = "#${palette.surface}";
      "panel.background" = "#${palette.surface}";
      "terminal.background" = "#${palette.surface}";
    };
  };
}
