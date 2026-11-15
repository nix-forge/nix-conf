# shellcheck shell=bash
export HOME="$TMPDIR/@name@"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_DIRS=@config_gtk_theme_package@/share
export GSETTINGS_BACKEND=memory GDK_BACKEND=x11
unset GTK_THEME
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$HOME/.themes"
cp @settings@ "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
cp @css@ "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
@pkgs_gnugrep@/bin/grep -q '^@define-color accent_color #' @css@
@pkgs_gnugrep@/bin/grep -q '^@define-color accent_color #' @flattened@/gtk-3.0/gtk-dark.css
@pkgs_gnugrep@/bin/grep -q '^gtk-application-prefer-dark-theme=@lib_boolToString_expectedDark@$' @settings@
echo '@name@: native GTK 3'
xvfb-run -a @python@/bin/python @probe@
ln -s @flattened@ "$HOME/.themes/@themeName@"
GTK_THEME="$(@pkgs_gnused@/bin/sed -n 's/^GTK_THEME=//p' @overrides@)"
export GTK_THEME
echo '@name@: flattened theme with Flatpak variant override'
xvfb-run -a @python@/bin/python @probe@
